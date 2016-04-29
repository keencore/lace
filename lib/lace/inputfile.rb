# This file implements Lace::InputFile

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
require 'pathname'

class Pathname
	def path
		self
	end
end

module Lace
	module PathMixin
		# The to_path function either takes a Pathname instance, which it returns as is,
		# or a String which it treats as a relative file path and for which it returns
		# an expanded Pathname.
		def to_path(filename)
			filename.is_a?(Pathname) ? filename : Pathname.new(filename).expand_path
		end
	end

	# The InputFile class is used to represent all files that are potetnial inputs
	# for compilers and their assiciated data.
	class InputFile
		# the path of the file (a Pathname)
		attr_reader :path
		# the Lace::Context in which this file was added
		attr_reader :context
		# an Array of tags associated with this file
		attr_accessor :tags
	
		def initialize(path, tags, context, ignore_ext=false)
			tags = tags.to_set
			if !ignore_ext
				ext = /\.[^.]+$/.match(path.to_s)
				tags << ext[0] if ext
			end
			@path = path
			@tags = tags
			@context = context
		end
		
		def to_path
			@path
		end

		def to_s
			""+@path.to_s+" [ "+@tags.to_a.join( ", " )+" ]"
		end
	end
end

