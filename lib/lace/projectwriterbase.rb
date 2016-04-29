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

require 'lace/project'
require 'lace/config'
require 'fileutils'
require 'open3'

module Lace
	class ProjectFileWriterBase
		include PathMixin
		attr_reader :project, :projects, :builds, :build_path
		attr_writer :build_path, :lace_bin

		def initialize(project_filename, builds,build_dir=nil)
			@lace_bin = to_path($0).dirname

			config = Lace::Config.load Pathname.new( __FILE__ )
			builds = Project.get_available_build_tags(project_filename) if builds.empty?

			@builds = builds
			@project_mapping = {}
			@projects = builds.map do |build|
				@project_mapping[build] = Lace::Project.load(project_filename, config, build.split('/'),build_dir)
			end
			@project = @projects.first
		end

		def get_host_platform()
            if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
                return :win32
            elsif (/darwin/ =~ RUBY_PLATFORM) != nil
                return :osx
            else
            	# :TODO: improve this..
                return :linux
            end
		end

		def get_build_executable_path(build)
			executable_base_filename = get_attribute(:executable_basename,build).first || (@project.globals.target_name || @project.name)
			executable_namer = get_attribute(:executable_name_creator, build).first
			executable_filename = executable_namer ? executable_namer.call(project, executable_base_filename) : executable_base_filename

			if get_host_platform == :win32
				executable_filename += ".exe"
			end

			return @project_mapping[build].build_path + executable_filename
		end

		def open_file(filename, &block)
			old_pwd = Dir.getwd
			FileUtils.mkpath(File.dirname(filename))
			Dir.chdir(File.dirname(filename))
			File.open(File.basename(filename), 'w', &block)
			Dir.chdir(old_pwd)
		end

		def get_attribute(id, build = nil)
			attributes = []
			(build ? [@project_mapping[build]] : @projects).each do |project|
				project.contexts.each do |context|
					attributes.concat(context.get_local_attributes(id))
				end
			end
			return attributes.uniq
		end

		def get_project_files(project)
			files = []

			if project then
				files.concat(project.files.map {|f| f.path })

				project.sub_projects.each do |subproject|
					files.concat( get_project_files( subproject ) )
				end
			end
			files
		end

		def get_project_modules(project)
			modules = []
			if project then
				modules.concat(project.modules)

				project.sub_projects.each do |subproject|
					modules.concat( get_project_modules( subproject ) )
				end
			end
			modules
		end

		def get_files(build = nil)
			files = []

			(build ? [@project_mapping[build]] : @projects).each do |project|
				files.concat( get_project_files( project ) )
			end
			return files.uniq
		end

		def get_modules(build=nil)
			modules = []
			(build ? [@project_mapping[build]] : @projects).each do |project|
				modules.concat( get_project_modules( project ) )
			end
			return modules.uniq
		end

		def find_project(build)
			@project_mapping[build]
		end

		def get_lace_bin()
			@lace_bin + 'lace'
		end

		def build_command(build, jobs = '1',quote_string="",keep_dirs=[])
			build_path_option = ' -p ' + @build_path.to_s if @build_path
			keep_dir_string = keep_dirs.map{|kd| "-k " + kd.to_s}.join(' ')
			"#{quote_string}#{Helpers::ruby_exe}#{quote_string} #{@lace_bin + 'lace'} -j #{jobs} #{keep_dir_string} -b #{build} #{find_project(build).filename}#{build_path_option || ''}"
		end
	end
end
