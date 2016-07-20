# Copyright (c) 2015 keen core
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module Lace
	class RemoteShell
		def initialize( blob_config, remote_host, remote_user, identity_file )
			@is_win32_host = (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil

			if !remote_user || ( !@is_win32_host && !identity_file  ) || !remote_host
				puts "remote_user=#{remote_user}"
				puts "identity_file=#{identity_file}"
				puts "remote_host=#{remote_host}"
				raise 'Invalid remote build config'
			end

			@remote_host = remote_host
			@remote_user = remote_user
			@identity_file = identity_file

			if @is_win32_host
				@rsync_path = Blob.fetch( blob_config, "core", "public/cwrsync/cwrsync-5.4.1", "d4d881cf5930b774e207c06e08af20aff55e248c" )				
				@rsync_binary = @rsync_path + 'cwrsync.cmd'
				@ssh_binary = @rsync_path + 'plink.exe'	
				@ssh_login = "#{@rsync_path}/cygnative.exe #{@rsync_path}/plink.exe -batch"
			else
				@rsync_binary = 'rsync'
				@ssh_binary = 'ssh'
				@ssh_login = "ssh -l #{@remote_user} -i #{identity_file}"
			end
		end
		
		def ssh_target(t)
			"#{@remote_user}@#{@remote_host}:#{t}"
		end

		def run_local(*args, &block)
			args = args.flatten
			args = args.map {|a| a.to_s}
			# quote arguments with spaces.
			#args = args.map {|a| / / =~ a ? '"'+a+'"' : a}.join(' ')
			args = args.join( ' ' )
			#puts "run_local (#{args})"			
			#puts "pwd = #{Dir.pwd}"

			unless args.empty?
				Open3.popen2e(args) do |stdin, stdout_err, wait_thr|
					#set_process_prio_to_below( wait_thr[:pid] )
					while line = stdout_err.gets
						if block 					 		
					 		block.call( line )
					 	else
					 		puts line
					 	end
					end
					exit_status = wait_thr.value
					unless exit_status.success?
						puts "build aborted - the following command failed with exitcode #{exit_status}:"
						# output the original arguments because visual studio crashes when the compiler path is relative...
						puts "%s", [args].flatten.join(' ')
						raise AbortBuild
					end
				end
			end
		end

		def encode_local_path(p)
			if @is_win32_host
				return "/cygdrive/#{p.gsub('\\', '/').gsub(':', '' )}"
			else 
				return p
			end
		end

		def run_remote(*cmd,&block)	
			if @is_win32_host
				run_local(@ssh_binary, '-t', '-l', @remote_user, @remote_host, *cmd, &block)
			else
				run_local(@ssh_binary, '-t', '-l', @remote_user, '-i', @identity_file, @remote_host, *cmd, &block)
			end
		end

		def rsync(src, target, excludes = [])	
		# todo: why do psd files fail??
			cmd = [@rsync_binary, '-v', '-r', '-t', '--delete', '--exclude=.git', '--exclude=*.psd', '--exclude=.svn', '--no-p', '--no-g', '--no-o', '-L', '--chmod=ugo=rwX', "-e='#{@ssh_login}'", src, ssh_target(target)]
			cmd << "--include='buildtools/lace/bin'"
			cmd += excludes.map { |e| "--exclude=#{e}" }
			run_local(cmd)
		end
	end
end

