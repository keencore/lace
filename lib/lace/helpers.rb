# Copyright (c) 2009 keen games
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

require 'open3'
require 'thread'
require 'rbconfig'

module Lace
	USE_PATHNAME_MAKE_RELATIVE = false
	PLATFORM_WIN32 = RUBY_PLATFORM =~ /win32|mingw32/
	USE_THREADS = !PLATFORM_WIN32

	class StdOutString < String; end
	class StdErrString < String; end

	module Helpers
		def self.make_relative(path)
			make_relative2(path, Pathname.pwd)
		end

		def self.set_process_prio_to_below( pid )
			if PLATFORM_WIN32
				begin
					toolpath = File.dirname(__FILE__) + "../../../../bin/win32_x64/setprocesspriobelow.exe"
					%x(#{toolpath} #{pid})
				rescue Exception => e
					# no need to do anything
				end
			end
		end

		def self.quote_path(path)
			path_string = path.to_s
			return / / =~ path_string ? '"'+ path_string +'"' : path_string
		end

		def self.normalize_path(path)
			path = path.expand_path

			if PLATFORM_WIN32
				if path.absolute? 
					# make first letter (drive letter) uppercase!
					ps = path.to_s
					ps[0] = ps[0].upcase
					path = Pathname.new( ps )
				end
			end
			return path
		end

		if USE_PATHNAME_MAKE_RELATIVE
			def self.make_relative2(path, from)
				path.relative_path_from(from).to_s
			end
		else
			def self.make_relative2(path, from)
				return path.to_s if path.to_s =~ /^(\w:)/ && from.to_s[0, 2].downcase != $1.downcase		# don't try to create a relative path to a different drive on win32
				basename = from.to_s
				path = path.to_s

=begin
				if PLATFORM_WIN32
					basename = basename.downcase
					path = path.downcase
				end
=end

				filenameparts = path.split(/\/|\\/)
				basenameparts = basename.split(/\/|\\/)

				if PLATFORM_WIN32
					until filenameparts.empty? || basenameparts.empty? || filenameparts.first.casecmp(basenameparts.first) != 0
						filenameparts.shift
						basenameparts.shift
					end

					return '.' if filenameparts.empty? && basenameparts.empty?
				else
					return '.' if filenameparts == basenameparts

					while filenameparts.first == basenameparts.first
						filenameparts.shift
						basenameparts.shift
					end
				end

				return ('..' + '/') * basenameparts.size + filenameparts.join('/')
			end
		end

		def self.is_child_dir_of(child, parent)
			path = self.make_relative2(child, parent)
			return Pathname.new(path).relative? && path !~ /^\.\./
		end

		TRACE_MUTEX = Mutex.new

		def self.sh(verbose, *args, &block)
			original_args = args;
			args = args.flatten.map do |arg|
				# use absolute path names cause of MAX_PATH
				case arg
				when Pathname, InputFile
					#make_relative(arg.path)
					arg.path.to_s
				else
					arg
				end
			end

			if verbose
				puts "pwd: #{Dir.pwd}"
				puts args.join(' ')
				$stdout.flush
			end

			# quote arguments with spaces.
			args = args.map {|a| / / =~ a ? '"'+a+'"' : a}.join(' ')

			Open3.popen2e(args) do |stdin, stdout_err, wait_thr|
				set_process_prio_to_below( wait_thr[:pid] )
				while line = stdout_err.gets
					if block
				 		block.call( [ line ] )
				 	else
				 		puts line
				 	end
				end
				exit_status = wait_thr.value
				if exit_status
					unless exit_status.success?
						exitcode = wait_thr.value.exitstatus
						trace "build aborted - the following command failed with exitcode #{exitcode}:"
						# output the original arguments because visual studio crashes when the compiler path is relative...
						trace "%s", [original_args].flatten.join(' ')
						raise AbortBuild
					end
				else
					# :JK: not sure when this can happen..
					trace "Warning: the following command didn't report a status message:"
					trace "%s", [original_args].flatten.join(' ')
				end
			end
		end

		@@mtimes = {}
		def self.mtime(name)
			name = name.path.to_s unless name.is_a?(String)
			@@mtimes[name] ||= File.mtime(name)
		end

		@@existing_files = {}
		def self.exist?(name)
			name = name.path.to_s unless name.is_a?(String)
			@@existing_files[name] ||= File.exist?(name)
		end

		def self.reset_file_status_hash
			@@mtimes = {}
		end

		def self.newer?(i, o)
			if i.is_a?(Array)
				return false if i.empty?
				itime = i.map do |iname|
					return true unless exist?(iname)
					mtime(iname)
				end.max
			else
				return true unless exist?(i)
				itime = mtime(i)
			end

			if o.is_a?(Array)
				o.each do |oname|
					return true unless exist?(oname) && mtime(oname) >= itime
				end
			else
				return true unless exist?(o) && mtime(o) >= itime
			end

			return false
		end

		def self.user_name()
			if PLATFORM_WIN32
				return ENV['USERNAME']
			else
				return ENV['USER']
			end
		end

		def self.trace(format, *args)
			args = args.map do |arg|
				(arg.is_a?(Pathname) || arg.is_a?(InputFile)) ? make_relative(arg.path) : arg
			end
			TRACE_MUTEX.synchronize do
				puts sprintf(format, *args)
				$stdout.flush
			end
		end

		def self.trace_error(callstack, format, *args)
			just_lace_callstack = callstack.select {|e| e =~ /\.lace\b/ }
			callstack = just_lace_callstack unless just_lace_callstack.empty?

			msg = sprintf(format, *args)
			trace "%s %s", format_callstack_entry(callstack.first), msg
			callstack[1..-1].each do |entry|
				trace "  from %s", format_callstack_entry(entry)
			end
		end

		def self.format_callstack_entry(entry)
			location = /^(.+):(\d+):/.match(entry)
			return entry unless location
			if PLATFORM_WIN32
				return sprintf "%s(%d):", location[1], location[2].to_i
			else
				return sprintf "%s:%d:", location[1], location[2].to_i
			end
		end

		def self.ruby_exe
			RbConfig::CONFIG['bindir'] + '/' + RbConfig::CONFIG['ruby_install_name'] + RbConfig::CONFIG['EXEEXT']
		end

		def self.callstack
			begin
				raise Exception
			rescue Exception => e
				return e.backtrace[1..-1]
			end
		end

		def self.numCPUs
			return ENV['NUMBER_OF_PROCESSORS'].to_i || 1 if PLATFORM_WIN32
			if File.exist?('/proc/cpuinfo')
				return [1, File.read('/proc/cpuinfo').scan(/^processor\s+:/).size].max
			elsif File.executable?("/usr/sbin/sysctl")
				return [1, File.popen("/usr/sbin/sysctl -n hw.ncpu").read.to_i].max
			end
			return 1
		end

		def self.default_blob_path
			 if PLATFORM_WIN32
			 	return "C:/keen_blobs"
			 else
			 	return Pathname.new("~") + "keen_blobs"
			 end
		end

		class TempEnv
			def initialize
				@old_values = {}
			end

			def []=(key, value)
				value = value.to_s if value.is_a?(Pathname)
				unless @old_values.include?(key)
					if ENV.include?(key)
						@old_values[key] = ENV[key]
					else
						@old_values[key] = :delete
					end
				end
				ENV[key] = value
			end

			def [](key)
				ENV[key]
			end

			def delete(key)
        if !@old_values.include?(key) && ENV.include?(key)
          @old_values[key] = ENV[key]
        end
				ENV.delete(key)
			end

      def clear()
        ENV.keys.each {|k| delete k}
      end

			def revert
				@old_values.each do |key, value|
					if value == :delete
						ENV.delete(key)
					else
						ENV[key] = value
					end
				end
			end
		end

		def self.temp_env
			env = TempEnv.new
			yield env
			env.revert
		end
	end
end

