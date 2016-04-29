# This file implements the Lace::Context class.

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

require 'set'

module Lace
	# Contexts hold attributes to be used by compilers.
	class Context
		attr_reader :base_path

		def initialize(project, parent,base_path)
			project.register_context(self)
			@parent = parent
			@imports = []
			@auto_tags = []
			@compiler_output_tags = []
			@attributes = {}
			@use_cache = false
			@cached_attributes = {}
			@base_path = base_path
		end
		
		def add_import(import)
			@imports << import
			raise "Don't change attributes after the context is closed" if @use_cache
		end
		
		def resolve_imports
			raise "Don't change attributes after the context is closed" if @use_cache
			@use_cache = true
			@imports = @imports.map do |import|
				next if import.is_a?(Project::Import) and !import.module
				import.is_a?(Project::Import) ? import.module.exports : import
			end.flatten
		end
		
		def add_attribute(id, *values)
			attribute = (@attributes[id] ||= [])
			raise "Trying to add values to scalar attribute #{id.inspect}" unless attribute.is_a?(Array)
			raise "Don't change attributes after the context is closed" if @cached_attributes.has_key?(id)
			attribute.concat(values)
		end
		
		def inspect
			me = "auto_tags=#{@auto_tags}, compiler_ouput_tags=#{@compiler_output_tags} attributes=#{@attributes}"
			@parent ? me + "\n parent: #{@parent.inspect}" : me 
		end
		
		def set_attribute(id, value)
			raise "Don't change attributes after the context is closed" if @cached_attributes.has_key?(id)
			@attributes[id] = value
		end

		def is_attribute_set(id)
			return @attributes.include?(id)
		end
		
		# this returns a list of uniq values of the attribute named by +id+ found in
		# this context and in all parent contexts
		def get_attribute_set(id)
			if @use_cache
				if not @cached_attributes.has_key?( id )
					@cached_attributes[id] = find_attribute_set( id )
				end
				return @cached_attributes[ id ]
			else
				result = find_attribute_set( id )
				return result
			end
		end
		
		# this returns a list of values of the attribute named by +id+ found in
		# this context and in all parent contexts
		def get_attribute_list(id)
			if @use_cache
				if not @cached_attributes.has_key?( id )
					@cached_attributes[id] = find_attribute_list( id )
				end
				return @cached_attributes[ id ]
			else
				return find_attribute_list( id )
			end	
		end

		def find_attribute_list(id)
			values = @parent ? @parent.get_attribute_list(id) : []
			@imports.each do |import|
				next if !import
				values.concat(import.get_attribute_list(id))
			end
			my_values = @attributes[id]
			if my_values
				if my_values.is_a?(Array)
					values.concat(my_values)
				else
					values << my_values
				end
			end
			return values
		end

		def find_attribute_set(id)
			values = @parent ? @parent.get_attribute_set(id).dup : Set.new
			@imports.each do |import|
				next if !import
				values.merge(import.get_attribute_set(id))
			end
			my_values = @attributes[id]
			if my_values
				if my_values.is_a?(Array)
					values.merge(Set.new my_values)
				else
					values << my_values
				end
			end
			return values
		end
		
		# this returns the first value found for the attribute named by +id+ in this
		# context or any of its parent contexts
		def get_attribute_value(id)
			if @use_cache
				if not @cached_attributes.has_key?( id )
					@cached_attributes[id] = find_attribute_value( id )
				end
				return @cached_attributes[ id ]
			else
				return find_attribute_value( id )
			end
		end

		def find_attribute_value(id)
			attribute = @attributes[id]
			return attribute.is_a?(Array) ? attribute.last : attribute if attribute
			@imports.each do |import|
				next if !import
				value = import.get_attribute_value(id)
				return value if value
			end
			return @parent ? @parent.get_attribute_value(id) : nil
		end
		
		# this returns a list of value defined for the attribute named by +id+ defined
		# in just this context
		def get_local_attributes(id)
			@attributes[id] || []
		end
		
		def add_auto_tags(tags, filter)
			@auto_tags << [[tags].flatten, filter]
		end
		
		def evaluate_auto_tags(tags)
			result = tags

			if not @auto_tags.empty?
				result = tags.dup
				@auto_tags.each do |new_tags, filter|					
					if filter == nil || filter.matches?(tags)
						new_tags.each {|t| 							
							result << t 
						}					
					end
				end
			end
			return @parent ? @parent.evaluate_auto_tags(result) : result
		end

		def add_compiler_output_tags(tags, filter)
			@compiler_output_tags << [[tags].flatten, filter]
		end
		
		def evaluate_compiler_output_tags(tags)
			result = tags

			if not @compiler_output_tags.empty?
				result = tags.dup
				@compiler_output_tags.each do |new_tags, filter|					
					if filter == nil || filter.matches?(tags)
						new_tags.each {|t| 							
							result << t 
						}					
					end
				end
			end
			return @parent ? @parent.evaluate_compiler_output_tags(result) : result
		end

	end
end

