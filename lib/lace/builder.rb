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

module Lace
	class Builder
		# builds the given project, executing up to num_jobs jobs in parallel
		#
		# note: To fully utilize parallel jobs you need to use at least ruby 1.9
		def build(project, num_jobs = 1)
			sub_project_files = []
			project.sub_projects.each do |sub_project|
				files = build(sub_project, num_jobs)
				if sub_project.output_filter
					files = sub_project.output_filter.call(files).map do |file|
						InputFile.new(file.path, file.tags, sub_project.parent_context)
					end
					sub_project_files.concat(files)
				end
			end

			project.evaluate_compiler_auto_tags

			compilers = project.compiler_set.sort

			# print list of compilers:
			#compilers.each {|c| p "c#{compilers.index( c )}: #{c.getInfo}"}

			files = {:out => []}
			compilers.each {|c| files[c] = [] }

			project_files = project.files.reject {|f| f.tags.include?('EXCLUDE') } + sub_project_files
			project_files.each {|f| files[project.compiler_set.find_compiler(f.tags) || :out] << f }
			compilers.each do |compiler|
				compiler.process_files_base(files[compiler], num_jobs)
				compiler.output_files_base(files[compiler]).each {|f|
					target_compiler = project.compiler_set.find_compiler(f.tags) || :out

					#if f.path.extname() == '.gles'
					#	p target_compiler.inspect
					#end

					if target_compiler != :out && compilers.index( compiler ) > compilers.index( target_compiler )
						p "compiler sort order problem detected!"
						p "the compiler #{compiler.getInfo} (index:#{compilers.index( compiler ).to_s}) producted the file"
						p f.path.to_s
						p "which matches the already completed compiler #{target_compiler.getInfo} (index: #{compilers.index( target_compiler ).to_s})"
						raise "it's broken!"
					end
					files[target_compiler] << f
				}
				compiler.finish_build_base()
			end

			pwd = Dir.getwd

			project.post_build_steps.each do |step, dir|
				Dir.chdir(dir)
				step.call
			end

			Dir.chdir(pwd)

			return files[:out]
		end

		# cleans all output files produced by compilers
		def clean(project)
			return unless File.exist?(project.build_path)
			printf "Cleaning build directory '%s'\n", project.build_path
			clean_dir(project.build_path,project.global_context.get_attribute_set( :sticky_build_directories ) )
		end

		# just clean whatever can be deleted and warn for entries that can't
		def clean_dir(path,stickyBuildDirs)
			stickyBuildDirs.map! { |x| x.downcase }
			Dir.new(path).each do |fname|
				next if fname == '.' || fname == '..'
				fname = path + fname
				if File.directory?(fname)
					begin
						# leave some directories
						if stickyBuildDirs.include?( fname.basename.to_s.downcase )
							puts "Keeping sticky build directory " + fname.to_s
						else
							FileUtils.rm_r(fname)
						end
					rescue Errno::EACCES
						clean_dir(fname,stickyBuildDirs)
					end
				else
					begin
						FileUtils.rm(fname)
					rescue Errno::EACCES
						printf "Warning: Unable to delete file '%s'.\n", fname
					end
				end
			end
		end
	end
end

