# This file implements the Lace::LaceModule class.

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

require 'lace/inputfile'

module Lace
	Todo = Struct.new( :name, :estimated_hours )
	Section = Struct.new( :block, :base_path )

	# The LaceModule class is used both to represent modules loaded by lace
	# and provides the context in which the .lace file is executed. As such,
	# most functions you call in your .lace files are defined in this class.
	class LaceModule
		include PathMixin
		# an Array of contexts this modules exports
		attr_reader :exports
		# the path of the directory the module was defined in
		attr_reader :path
		attr_reader :sections
		attr_reader :importlist
		attr_reader :owners
		attr_reader :todos
		attr_reader :main_context
		attr_reader :module_name

		def initialize(project, path, options, module_name)
			@path = path
			@project = project
			@options = options
			@owners = []
			@todos = []
			@build_tags = project.build_tags
			@exports = []
			@main_context = Context.new(project, project.global_context,nil)
			@current_base_path = nil
			@current_context = @main_context
			@sections = {}
			@module_name = module_name
			@importlist = []
			@current_section_name = "main"
			@licenses = []
		end

		# The import method adds the named module to a list of modules to be loaded.
		# All exported contexts of the imported modules will be added as a parent
		# context to the context inhiritance chain of this context.
		#
		def import(module_name)
			module_name = @module_name + module_name if module_name =~ /^#/
			module_name = @project.resolve_module_alias( module_name )
			@current_context.add_import(@project.add_import(module_name, self,false))
			source_module_name = ( @module_name || @project.to_s ) + '#' + @current_section_name
			@importlist << [ module_name, source_module_name ]
		end

		def owner(name)
			@owners << name
		end

		def todo( name, estimated_hours = 0 )
			@todos << Todo.new( name, estimated_hours )
		end

		def revision(revision_id)
			@project.set_module_revision(@module_name,revision_id)
		end

		# The import_weak method adds the named module to a list of modules to be loaded
		# IF the module can't be found the module import will just be ignored.
		def import_weak(module_name)
			@current_context.add_import(@project.add_import(module_name, self,true))
		end

		# The module_options method takes a module name and a hash of options and will
		# associate these options with the module.
		# You can call module_options multiple times for the same module, in which case
		# the option hash will be merged. Only overwriting the same option with a different
		# value will not work.
		#
		# The imported module can access its options through the @options variable
		def module_options(module_name, options)
			@project.add_module_options(module_name, options, self)
		end

		# The export method creates a new Lace::Context as a parent of the current context,
		# add this new context to the list of exported contexts and yields the given block with
		# the new context as the current one.
		#
		# This means that any imports and attributes added inside the export block are available
		# both to the current module and to any module importing this module.
		def export
			old_context = @current_context
			@current_context = Context.new(@project, nil,@current_base_path)
			@exports << @current_context
			yield
			old_context.add_import(@current_context)
			@current_context = old_context
		end

		# The context method creates a new context with the current context as its parent and
		# yields the given block with the new block as the current context.
		#
		# This means that any imports and attributes added inside this block are only available
		# to the files added inside it.
		def context
			old_context = @current_context
			@current_context = Context.new(@project, old_context,@current_base_path)
			yield
			@current_context = old_context
		end

		def third_party_local(local_path)
			raise "Local Third Party path #{local_path} does not exist!" if !File.exists? local_path
			raise "No Nesting of Third party paths allowed" if @current_base_path

			last_base_path = @current_base_path
			@current_base_path = local_path
			yield
			@current_base_path = last_base_path
		end

		def add_blob(server_id,blob_path,content_hash)
			return @project.add_blob(server_id,blob_path, content_hash)
		end

		def add_license(license_type)
			raise "Invalid license '#{license_type.to_s}'" if !@project.has_license_type? license_type
			@licenses << license_type
		end

		def get_licenses()
			return @licenses
		end

		def third_party_blob(server_id,blob_path,content_hash,license)

			# add this blob to the download list
			local_path = @project.add_blob(server_id,blob_path, content_hash)

			last_base_path = @current_base_path
			@current_base_path = local_path
			yield
			@current_base_path = last_base_path

			add_license( license ) if license

			return local_path
		end

		def run_section( section_name )
			@current_section_name = section_name
			section = @sections[section_name]
			if section
				@current_base_path = section.base_path
				section.block.call
				@current_base_path = nil
			end
			@current_section_name = ""
		end

		# The add_file method adds one or more files specified by a path with wildcards.
		# All files matching these wildcards are added with the space seperated tags given
		# as the second parameters.
		# If no files match, the default is to generate an error. This can be overridden
		# giving either :warn or :ignore_missing as third parameter.
		#
		# In most cases you will use the syntactic sugar
		#
		#   ! source/**/*.cpp TAG1 TAG2
		#
		# instead of
		#
		#   add_file('source/**/*.cpp', 'TAG1 TAG2')
		def add_file(glob, tags, error_mode = :error)
			tags = tags.split
			glob = adjust_path( glob )
			files = Dir[glob.to_s]
			if files.empty?
				msg = "No files found for pattern '#{glob}'."
				if error_mode == :error
					raise LaceError.new(msg)
				elsif error_mode != :ignore_missing
					Helpers.trace_error Helpers.callstack, "Warning: %s", msg
				end
			end
			files.each do |filename|
				path = to_path(filename)
				file_tags = tags.to_set
				ext = /\.[^.]+$/.match(path.to_s)
				file_tags << ext[0] if ext
				file_tags = @current_context.evaluate_auto_tags(file_tags)
				@project.add_file(InputFile.new(path, file_tags, @current_context))
			end
		end

		# The add_path methods adds one or more paths to the attribute named by +id+.
		def add_path(id, *paths)
			paths = paths.map {|path| to_path(adjust_path(path)) }
			@current_context.add_attribute(id, *paths)
		end

		# This methods sets the value of an attribute to a path. Attributes set in this way
		# cannot be changed in the same context. I'm unsure whether having this method
		# actually makes sense. This might be removed in later versions of Lace.
		def set_path(id, path)
			@current_context.set_attribute(id, to_path(adjust_path(path)))
		end

		# The add_attribute method adds one or more values to the attribute named by +id+.
		#
		# If you are adding a file path, please use +add_path+ instead.
		def add_attribute(id, *attr)
			@current_context.add_attribute(id, *attr)
		end

		# This methods sets the value of an attribute. Attributes set in this way
		# cannot be changed in the same context. I'm unsure whether having this method
		# actually makes sense. This might be removed in later versions of Lace.
		def set_attribute(id, attr)
			@current_context.set_attribute(id, attr)
		end

		def is_attribute_set(id)
			@current_context.is_attribute_set(id)
		end

		# The add_path methods adds one or more paths to the attribute named by +id+ in the
		# project global context, which is a parent of all other contexts.
		def add_global_path(id, *paths)
			paths = paths.map {|path| to_path(adjust_path(path)) }
			@project.global_context.add_attribute(id, *paths)
		end

		# This methods sets the value of an attribute to a path in the global context.
		# Attributes set in this way
		# cannot be changed in the same context. I'm unsure whether having this method
		# actually makes sense. This might be removed in later versions of Lace.
		def set_global_path(id, path)
			@project.global_context.set_attribute(id, to_path(adjust_path(path)))
		end

		# The add_attribute method adds one or more values to the attribute named by +id+
		# in the project global context, which is a parent of all other contetxts.
		#
		# If you are adding a file path, please use +add_path+ instead.
		def add_global_attribute(id, *attr)
			@project.global_context.add_attribute(id, *attr)
		end

		# This methods sets the value of an attribute in the global context. Attributes set in this way
		# cannot be changed in the same context. I'm unsure whether having this method
		# actually makes sense. This might be removed in later versions of Lace.
		def set_global_attribute(id, attr)
			@project.global_context.set_attribute(id, attr)
		end

		# The define_compiler method creates a new compiler class and an instance of this class
		# and then runs the given block in the context of this instance to define/overwrite
		# its methods.
		#
		# The first parameter is the base class for the new compiler, the usual options are
		# Lace::CompilerBase, Lace::SingleFileCompiler and Lace::MultiFileCompiler.
		#
		# The second parameter is a hash of options. All option keys are hashes, and these
		# are the available options:
		#
		# input_pattern:: A Lace::Tag pattern that specifies which input files this compiler takes
		# dependency_pattern:: A pattern for files that this compiler uses (and that might be produced
		#                      by other compilers) but that should not be passed to the compile method.
		# output_name:: An output name/path or a pattern for an output name/path (where '%' is replaced
		#               by the base name of the input file). The extension of this name will be added to
		#               the output tags for this compiler.
		# output_dir:: The subdirectory in the build directory used for outputs of this compiler.
		#              This is not needed if you already give an output_name.
		# output_tag:: An output tag for the outputs of this compiler
		# output_tags:: An Array of output tags
		# verbose:: A flag to to tell the compiler whether to always output the command lines when
		#           executing external programs. The default is not to output anything except when
		#           the execution fails.
		#
		# At least one output tag has to be provided, through :output_name, :output_tag or :output_tags.
		def define_compiler(base_class, args, &block)
			compiler_class = Class.new(base_class)
			compiler_class.class_eval(&block)
			compiler = compiler_class.new(args)
			output_dir = ''
			output_tags = []
			if args[:output_dir]
				output_dir = args[:output_dir]
			elsif args[:output_name]
				output_dir, args[:output_name] = File.split(args[:output_name])
				output_tags << $1 if args[:output_name] =~ /(\.[^\.]+)$/
			end
			output_tags << args[:output_tag] if args[:output_tag]
			output_tags.concat(args[:output_tags]) if args[:output_tags]

			raise LaceError.new("Compiler definition is missing an :input_pattern") unless args[:input_pattern]

			add_compiler(output_dir, compiler, args[:input_pattern], args[:dependency_pattern], output_tags)
			return compiler_class
		end

		def add_compilertag_to_whitelist( tag )
			@project.add_compilertag_to_whitelist( tag )
		end

		# This is just a convinience function to create a tag. tag(value is the same as Tag.new(value).
		def tag(value)
			Tag.new(value)
		end

		# this adds the given path to the module search path
		def module_search_path(path)
			@project.add_import_path(path)
		end

		# The module_alias method adds a module alias to the project. This means, that whenever you
		# write import 'new_name', it internally imports old_name instead.
		def module_alias(new_name, old_name)
			@project.add_module_alias(new_name,old_name)
		end

		def module_alias_weak(new_name, old_name)
			@project.add_weak_module_alias(new_name, old_name)
		end

		# This executes the file at the given path in the current context. In contrast to an
		# import, the code is executed immideately, so that you can define new methods or
		# change the @build_tags that are then available to the code after the inject statement.
		def inject(name)
			filename = to_path(name)
			filename = @project.find_module(name, 'inject.def') unless filename.file?
			instance_eval(filename.read, filename.to_s)
			@project.add_used_file(filename)
		end

		# The define_subproject method creates a new project inline in the current module.
		# It takes one name parameter, which is used as a subdirectory for the compiler
		# outputs, and it takes an optional hash of named parameters.
		#
		# It will create a new project which by default gets the module_import_paths
		# and module_aliases of the parent project and executes the given block in the
		# context of this new project.
		#
		# The following named parameters exist:
		#
		# build_tags:: if this option exists, it will be used as the build tags of the sub-project,
		#              otherwise the build tags of the parent project are used.
		# output_filter_tags:: if this exists, the output files that match this tag pattern, are
		#                      promoted from the sub-project to the parent project.
		def define_subproject(name, params = {}, &block)
			@project.define_subproject(name, params, @current_context, block)
		end

		# Registers a block to be called after the build has finished
		def post_build_step(&block)
			@project.post_build_steps << [block, Dir.pwd]
		end

		# Registers a set of tags to add to files added in this context or child contexts.
		#
		# The parameters are the tags as Strings and optionally a Hash with options as last parameter.
		# The available options are:
		# filter:: A tag filter to restrict that files to which to add these tags
		def add_auto_tags(*params)
			tags, options = params.partition {|p| p.is_a? String }
			filter = nil
			unless options.empty?
				options.first.each_pair do |key, value|
					case key
					when :filter
						filter = value
					else
						raise LaceError.new("Unknown option :#{key} for add_auto_tags")
					end
				end
			end
			@current_context.add_auto_tags(tags, filter)
		end

		def add_global_auto_tags(*params)
			tags, options = params.partition {|p| p.is_a? String }
			filter = nil
			unless options.empty?
				options.first.each_pair do |key, value|
					case key
					when :filter
						filter = value
					else
						raise LaceError.new("Unknown option :#{key} for add_auto_tags")
					end
				end
			end
			@project.global_context.add_auto_tags(tags, filter)
		end

		def add_compiler_output_tags(*params)
			tags, options = params.partition {|p| p.is_a? String }
			filter = nil
			unless options.empty?
				options.first.each_pair do |key, value|
					case key
					when :filter
						filter = value
					else
						raise LaceError.new("Unknown option :#{key} for add_auto_tags")
					end
				end
			end
			@current_context.add_compiler_output_tags(tags, filter)

			@project.add_compiler_auto_tag(tags,filter)
		end

		def add_global_compiler_output_tags(*params)
			tags, options = params.partition {|p| p.is_a? String }
			filter = nil
			unless options.empty?
				options.first.each_pair do |key, value|
					case key
					when :filter
						filter = value
					else
						raise LaceError.new("Unknown option :#{key} for add_auto_tags")
					end
				end
			end
			@project.global_context.add_compiler_output_tags(tags, filter)

			@project.add_compiler_auto_tag(tags,filter)
		end

		def section(name, &block)
			@sections[name] = Section.new( block, @current_base_path )
		end

		def base_path()
			return @current_base_path || @current_context.base_path
		end

		def adjust_path(local_path)
			module_base_path = base_path
			if module_base_path
				#p "base_path=#{module_base_path.to_s}"
				result = module_base_path + local_path
				#p "adjusting local path #{local_path.to_s} to #{result.to_s}"
				return result
			else
				return local_path
			end
		end

	private

		def add_compiler(output_dir, compiler, input_pattern, dependency_pattern, output_tags)
			compiler.project = @project
			compiler.module = self
			compiler.output_path = @project.build_path + output_dir
			compiler.input_pattern = input_pattern
			compiler.dependency_pattern = dependency_pattern
			compiler.output_tags = to_tags(output_tags)
			compiler.path = @path
			@project.add_compiler( compiler )
		end

		def to_tags(list)
			list = [list] unless list.is_a?(Array)
			list.map do |tag|
				case tag
				when Tag, TagAnd, TagOr
					tag
				else
					Tag.new(tag)
				end
			end
		end
	end
end

