# This file defines the tag related classes:
# * Lace::Tag
# * Lace::TagAnd
# * Lace::TagOr

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
	# The Tag class is used to construct patterns to match against lists of tags
	#
	# In your .lace files you usually construct tags through the tag(string) convinience function.
	# Tags can be combined using the | (or) and & (and) operators, so a pattern that matches c and
	# c++ files could be written like this:
	#
	#   tag('.c') | tag('.cpp')
	#
	# And a pattern that only matches c++ files tagged to be used in unit test could be written:
	#
	#  tag('.cpp') & tag('UNITTEST')
	class Tag
		attr_reader :value
		
		def initialize(value)
			@value = value			
		end
		
		def &(o)
			TagAnd.new(self, o)
		end
		
		def |(o)
			TagOr.new(self, o)
		end

		def !()
			TagNot.new(self)
		end


		# the matching operator used in the case construct, so that you can write:
		#
		#   case @build_tags
		#   when tag('win32')
		#     ..
		#   when tag('ps3')
		#     ..
		#   end
		def ===(tag_list)
			tag_list.any? do |tag|
				tag.is_a?(Tag) ? @value === tag.value : @value === tag
			end
		end
		
		# tests whether a list of tags matches this pattern
		def matches?(tag_list)
			self === tag_list
		end
		
		# returns a score for the match to a list of tags. The higher the score, the more specific the match.
		def match(tag_list)
			tag_list.inject(0) {|acc, tag| acc + ((tag.is_a?(Tag) ? @value === tag.value : @value === tag) ? 1 : 0) }
		end
		
		def to_s
			value
		end
	end
	
	class TagAnd
		def initialize(a, b)
			@a = a
			@b = b
		end
		
		def &(o)
			TagAnd.new(self, o)
		end
		
		def |(o)
			TagOr.new(self, o)
		end
		
		def !()
			TagNot.new(self)
		end

		def ===(tag_list)
			@a === tag_list && @b === tag_list
		end
		
		def matches?(tag_list)
			self === tag_list
		end
		
		def match(tag_list)
			a = @a.match(tag_list)
			b = @b.match(tag_list)
			(a > 0 && b > 0) ? a + b : 0
		end
		
		def to_s
			"(#{@a})&(#{@b})"
		end
	end
	
	class TagOr
		def initialize(a, b)
			@a = a
			@b = b
		end
		
		def &(o)
			TagAnd.new(self, o)
		end
		
		def |(o)
			TagOr.new(self, o)
		end
		
		def !()
			TagNot.new(self)
		end

		def ===(tag_list)
			@a === tag_list || @b === tag_list
		end
		
		def matches?(tag_list)
			self === tag_list
		end
		
		def match(tag_list)
			[@a.match(tag_list), @b.match(tag_list)].max
		end
		
		def to_s
			"(#{@a})|(#{@b})"
		end		
	end
	
	class TagNot
		def initialize(child)
			@child = child
		end
		
		def &(o)
			TagAnd.new(self, o)
		end
		
		def |(o)
			TagOr.new(self, o)
		end
		
		def !()
			TagNot.new(self)
		end

		def ===(tag_list)
			!(@child === tag_list)
		end
		
		def matches?(tag_list)
			!(@child === tag_list)
		end
		
		def match(tag_list)
			matches?(tag_list) ? 1 : 0
		end
		
		def to_s
			"!#{@child}"
		end		
	end
end

