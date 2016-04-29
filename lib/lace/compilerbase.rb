# This file defines the following base classes used in compiler definitions:
# * Lace::CompilerBase
# * Lace::SingleFileCompiler
# * Lace::MultiFileCompiler

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

require 'tsort'
require 'thread'
require 'lace/helpers'
require 'lace/dependencies'
require 'tempfile'

# The Lace namespace
module Lace
	# This is a simple exception thrown to abort the build. Throwing this will make
	# sure that jobs executing in parallel are stopped as well.
	class AbortBuild < Exception
	end

	# The base class that should be used for all compiler definition.
	#
	# Child classes have to provide the process_files(files, num_jobs) and
	# output_files(files) methods.
	#
	# process_files should compile all given files and output_files should return an
	# Array of InputFile instances for each output the compiler produces for the
	# given input files.
	class CompilerBase
		# The input tag filter, see tag.rb
		attr_accessor :input_pattern
		# An array of tags this compiler produces
		attr_accessor :output_tags
		# The path this compiler should place its outputs in
		attr_writer :output_path
		# The project in which this compiler was defined
		attr_writer :project
		# The module in which this compiler was defined
		attr_writer :module
		# A flag controlling whether the compiler should print verbose output when compiling
		attr_writer :verbose
		attr_accessor :dependency_pattern
		attr_writer :path

		def initialize(args)
			@args = args
			@verbose = args[:verbose]
			@dependencyFiles = {}
		end

		# Returns whether the given array of tags match the input tags of this
		# compiler. If they do match the quality of the match is returned as
		# a number, otherwise nil is returned.
		def tags_match?(tags)
			count = @input_pattern.match(tags)
			if @dependency_pattern
				count += @dependency_pattern.match(tags)
			end
			count > 0 ? count : nil
		end

		# tries to return a somewhat meaningful string for this compiler. needs to be improved
		def inspect
			if @args[:name]
				sprintf "Compiler(%s)", @args[:name]
			else
				sprintf "Compiler(%s => %s)", input_pattern.inspect, output_tags.inspect
			end
		end

		# called from the outside (usually Builder::build) to start processing this compilers
		# files. this method should not be overwritten by child classes.
		def process_files_base(files, num_jobs = 1)
			files = files.select {|f| @input_pattern.matches?(f.tags) }
			Helpers.reset_file_status_hash
			@output_path.mkpath
			begin
				process_files(files, num_jobs)
			rescue AbortBuild
				exit 1
			end
		end

		def output_files_base(files)
			files = output_files(files.select {|f| @input_pattern.matches?(f.tags) })
			files.each do |f|
				f.tags = f.context.evaluate_compiler_output_tags( f.tags )
			end
			if $log
				if files.empty?
					$log.debug("#{self.inspect} returns no files as output")
				else
					filenames = files.map {|f| Helpers::make_relative(f.path) }
					$log.debug("#{self.inspect} returns these files as output:")
					filenames.each {|f| $log.debug("  #{f}") }
				end
			end
			return files
		end

		def evaluate_auto_tags(auto_tags)
			auto_tags.each do |new_tags, filter|
				if filter == nil || filter.matches?(@output_tags)
					new_tags.each do |t|
						@output_tags << tag( t )
					end
				end
			end
		end

		def finish_build_base()
			begin
				finish_build()
			rescue AbortBuild
				exit 1
			end
		end

		def finish_build()
		end

		def getInfo()
			return @module.path.to_s + ': ' + ( @input_pattern.to_s ? @input_pattern.to_s : 'nil' ) + ' => '+ @output_tags.to_s + ' (' + @output_path.to_s + ')'
		end

	private

		# helper method to act as a shortcut to Tag.new(value) in compiler definitions
		def tag(value)
			Tag.new(value)
		end

		# helper method returning the given path relative to the current working directory.
		# This can be used to shorten the command lines when excecuting external compilers.
		def make_relative(path)
			Helpers.make_relative(path)
		end

		# helper method that wraps Kernel::system, aborting the build when the command was
		# not successful
		def sh(*args, &block)
			Helpers.sh(@verbose, *args, &block)
		end

		# prints the given line to stdout, the parameters are the same as for Kernel::printf.
		# please use this rather than printf as it is important to flush stdout after each
		# line which printf doesn't do
		def trace(*args)
			Helpers.trace(*args)
		end

		# this writes the given arguments into a temporary file and calls the given
		# executable with the temp filename prefixed by @. This can be used with
		# most compilers in case that otherwise the command line would become too long.
		def response_sh(exe, *args, &block)
			file = Tempfile.new('lace')
			args = args.map do |arg|
				if arg.is_a?(Set)
					arg = arg.to_a
				else
					arg
				end
			end
			args = args.flatten.map do |arg|
				if arg.is_a?(Pathname)
					arg = make_relative(arg)
				end
				if arg =~ /\s/
					arg = '"' + arg + '"'
				end
				arg
			end
			# quote arguments with spaces.
			file.write args.map {|a| / / =~ a ? '"'+a+'"' : a}.join(' ')
			file.close
			if @verbose
				puts 'using response file:', File.read(file.path)
			end
			begin
				Helpers.sh(@verbose, exe, '@' + file.path, &block)
			rescue AbortBuild
				puts 'contents of the response file :'
				puts args.join(' ')
				raise AbortBuild
			end
				file.delete
		end

		# This checks whether the given input file, or any of the source files in the
		# .d file are newer than any of the output files in the .d file
		#
		# If any of the input files are newer, it yields to the given block
		#
		# This method assumes the .d file is in the makefile format
		def check_dependencies(infile, dfile, compiler=nil)
			if File.exist?(dfile)
				dependencies = Dependencies.load_make_dependencies(dfile)
				dependencies.add_input(infile)
				dependencies.add_input(compiler) if compiler
				yield if dependencies.newer?
			else
				yield
			end
		end

		def loadDependencyFiles( dFiles )
			basepath = @project.build_path
			dFiles.each do |dFile|
				@dependencyFiles[ dFile ] = Dependencies.load_lace_dependencies(basepath,dFile)
			end
		end
		# This checks whether the given input file, or any of the source files in the
		# .d file are newer than any of the output files in the .d file
		#
		# If any of the input files are newer, it yields to the given block
		#
		# This does basically the same opperation as the check_dependencies method, but it
		# assumes that the .d file is in the following format which is a lot faster to parse:
		#
		# outfile1;outfile2;outfile3;...|infile1;infile2;infile3;...
		#
		# you can convert makefile format .d files to this format using create_optimized_dependencies
		def check_optimized_dependencies(infile, dfile, compiler=nil)

			basepath = @project.build_path

			if @dependencyFiles.has_key?( dfile )
				dependencies = @dependencyFiles[ dfile ]
			elsif File.exist?(dfile)
				dependencies = Dependencies.load_lace_dependencies(basepath,dfile)
			end

			needs_build = false

			verbose = @verbose

			# check if we have different inputs:
			if !dependencies
				p "#{infile}: no (valid) dependency file" if verbose
				needs_build = true
			elsif( infile and not dependencies.has_input?( infile ) )
				p "#{infile}: different input file infile=#{infile} d=#{dependencies.to_s}" if verbose
				needs_build = true
			elsif( compiler and not dependencies.has_input?( compiler ) )

				p "#{infile}: different compiler" if verbose
				needs_build = true
			elsif dependencies.newer?
				p "#{infile}: some input file is newer than an output file" if verbose
				needs_build = true
			else
				#p "#{infile}: up to date!" if verbose
			end

			if needs_build
				yield
			end
		end

		def write_optimized_dependencies(dependencies,dfile)
			basepath = @project.build_path
			dependencies.write_lace_dependencies(basepath, dfile)
		end

		# this converts a makefile format .d file to the optimized format read by
		# check_optimiized_dependencies
		def create_optimized_dependencies(basepath,file, compiler=nil)
			dependencies = Dependencies.load_make_dependencies(file).write_lace_dependencies(basepath,file)
			dependencies.add_input(compiler) if compiler
		end

		# This is a helper function to help compilers execute mutliple jobs in parallel.
		# The given block is called in num_jobs threads and all threads are stopped if the
		# AbortBuild exception is thrown.
		def threaded(num_jobs)
			if num_jobs > 1
				threads = (0...num_jobs).map do
					Thread.new do
						begin
							yield
						rescue AbortBuild
							threads.each {|t| t.exit if Thread.current != t }
							exit 1
						end
					end
				end
				threads.each {|t| t.join }
			else
				yield
			end
		end

		# traces a error message (see trace) if any arguments are given, then throws
		# an AbortBuild exception.
		def abort_build(*args)
			trace(*args) unless args.empty?
			raise AbortBuild
		end

		def output_name(file = nil)
			if file && @args[:output_name] !~ /%/
				raise "Output name '#{@args[:output_name]} needs to contain a '%'. (compiler: #{self.inspect})"
			end
			if file
				@output_path + @args[:output_name].sub(/%/, (file.context.get_attribute_value(:output_prefix) || '') + file.path.basename('.*').to_s)
			else
				@output_path + @args[:output_name]
			end
		end
	end

	# A base class for compilers that process each input file in a seperate step (ex, a c compiler).
	# This class automatically handles processing multiple jobs in parallel and calls the compile
	# method of the child class for each input file.
	#
	# The compile method has to take the input file (of class InputFile) as its first parameter
	# and the output filename (a Pathname) as its second.
	#
	# The output filename is generated by changing the extension of the input filename to the
	# extension given in the constructor and placing this file in the output path of the compiler.
	class SingleFileCompiler < CompilerBase
		# This method calls compile(file, output_filename) in the child class for each input file
		def process_files(files, num_jobs)
			files = files.dup
			mutex = Mutex.new

			threaded(num_jobs) do
				loop do
					file = nil
					mutex.synchronize { file = files.shift }
					break unless file
					if @args[:make_dependencies]
						check_dependencies(file, @project.build_path + @args[:make_dependencies].sub(/%/, file.path.basename('.*').to_s)) do
							compile(file, output_name(file))
						end
					elsif @args[:lace_dependencies]
						check_optimized_dependencies(file, @project.build_path + @args[:lace_dependencies].sub(/%/, file.path.basename('.*').to_s)) do
							compile(file, output_name(file))
						end
					else
						compile(file, output_name(file))
					end
				end
			end
		end

		# returns an Array of output files for the given input files
		def output_files(files)
			files.map {|f| InputFile.new(output_name(f), @output_tags, f.context) }
		end
	end

	# A base class for compilers that process all of their input files in a single step
	# (ex. a linker).
	#
	# A child class should provide a output_name method returning the filename of the output of
	# of the compiler and a compile function that processes the given files.
	class MultiFileCompiler < CompilerBase
		def process_files(files, num_jobs)
			compile(files) if Helpers.newer?(files, output_name)
		end

		def output_files(files)
			[InputFile.new(output_name, @output_tags, @project.global_context)]
		end
	end

	class CompilerSet
		include TSort		
		def initialize
			@compilers = []
			@compiler_tag_map = Hash.new
		end

		def <<(compiler)
			@compilers << compiler
			self
		end

		def find_compiler(tags,verbose=false)
			tags_hash = tags.hash
			if tags_hash == 0
				return nil
			end
			
			if !@compiler_tag_map.include?(tags_hash)
				best_match = nil
				best_match_value = 0
				if verbose
					puts tags_hash.to_s + " [" + tags.to_a.join(", ") + "]:"
				end
				@compilers.each do |c2|
					m = c2.tags_match?(tags)
					if m 
						if verbose
							puts "#{m}: #{c2.inspect}"
						end
						if !best_match || m > best_match_value
							best_match = c2
							best_match_value = m;
						end
					end
				end			
				
				@compiler_tag_map[tags_hash] = best_match
			end
			
			return @compiler_tag_map[tags_hash]
		end

		def find_compilers(tags)
			matches = []
			@compilers.each do |c2|
				if c2.tags_match?(tags)
					matches << c2
				end
			end
			return matches
		end

		def evaluate_compiler_auto_tags(auto_tags)
			@compilers.each do |compiler|
				compiler.evaluate_auto_tags(auto_tags)
			end
		end

		def sort
			@children = Hash.new {|h, k| h[k] = [] }
			@compilers.each do |c1|

				# add only the best compiler as child
				#best_match = find_compiler(c1.output_tags)
				#@children[best_match] << c1 if best_match

				# add all compiler as children
				matches = find_compilers(c1.output_tags)
				matches.each do |match|
					@children[match] << c1
				end
			end
			result = tsort

			#result.each {|c|p c.getInfo}

			return result
		end

		def tsort_each_node(&block)
			@compilers.each(&block)
		end

		def tsort_each_child(node, &block)
			@children[node].each(&block)
		end
	end
end

