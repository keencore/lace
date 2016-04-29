require 'set'
require 'thread'
require 'lace/helpers'

module Lace
	class Dependencies
		attr_reader :inputs, :outputs

		READ_MUTEX = Mutex.new # possible workaround for a ruby bug

		def initialize
			@inputs = []
			@outputs = []
		end

		def get_big_drive_letter( pathString )
			if pathString =~ /^(\w:)/ 
				pathString[ 0 ] = pathString[ 0 ].upcase
			end
			return pathString
		end

		def add_input(filename)
			@inputs << get_big_drive_letter( filename.to_s )
		end

		def add_output(filename)
			@outputs << get_big_drive_letter( filename.to_s )
		end

		def has_input?(input)
			@inputs.include?( get_big_drive_letter( input.to_s ) )
		end

		def newer?
			@outputs.empty? || ( !@inputs.empty? && Helpers.newer?(@inputs, @outputs) )
		end

		def expand_paths
			@inputs = @inputs.map {|path| File.expand_path(path.to_s) }
			@outputs = @outputs.map {|path| File.expand_path(path.to_s) }
		end

		def to_s
			"inputs: #{@inputs.join(',')} outputs: #{@outputs.join(',')}"
		end

		def write_lace_dependencies(basepath,filename)
#p "write dep: basepath=#{basepath}"
			relative_outputs = outputs.map{ |o| Helpers::make_relative2( o, basepath ) }.join( ';' )
			relative_inputs = inputs.map{ |i| Helpers::make_relative2( i, basepath ) }.join( ';' )

			written = false
			until written == true
				begin
					File.open(filename, 'w') {|f|
						f.write relative_outputs + '|' + relative_inputs
					}
					written = true
				rescue Errno::EBADF
					# do nothing. This happens occasionally, we don't know why.
				end
			end

=begin
			test_dependencies = Dependencies.load_lace_dependencies(basepath,filename)

			if( test_dependencies.inputs != inputs )
				puts "iold=#{inputs}"
				puts "inew=#{test_dependencies.inputs}"
				raise 'input mismatch'
			end

			if( test_dependencies.outputs != outputs )
				puts "oold=#{outputs.join(',')}"
				puts "onew=#{test_dependencies.outputs.join(',')}"
				raise 'output mismatch'
			end
=end
		end

		def self.load_lace_dependencies(basepath,filename)
#p "load dep: basepath=#{basepath}"
			dependencies = Dependencies.new
			if File.exists?( filename )
				file = File.read(filename)

				o, i = file.chomp.split('|')
				o.split(';').each {|output| dependencies.add_output(basepath+output) } if o
				i.split(';').each {|input| dependencies.add_input(basepath+input) } if i
			end
			return dependencies
		end

		# parses a makefile format dependencies file and returns a Dependencies instance
		def self.load_make_dependencies(filename)
			dependencies = self.new
			file = File.read(filename)
			regexp = nil
			if (file.count(':') > 1)
				regexp = /("[^"]+"|[^"]+): (.*)/
			else
				regexp = /("[^"]+"|[^":]+):(.*)/
			end

			file.gsub(/\\\n/, ' ').scan(regexp) do |o, i|
				i = i.scan(/("[^"]+"|(\\ |\S)+)/).map {|d| d.first.gsub(/\\ /, ' ') }
				o.strip!
				o = o[1...-1] if o =~ /^".*"$/
				i = i.map do |n|
					n =~ /^".*"$/ ? n[1...-1] : n
				end
				i.each {|input| dependencies.add_input(input) }
				dependencies.add_output(o)
			end
			dependencies.expand_paths
			return dependencies
		end
	end
end

