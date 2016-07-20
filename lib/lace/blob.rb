require 'fileutils'
require 'pathname'
require 'digest/sha1'
require 'lace/helpers'

def blob_content_filename()
	return 'lace-blob.hash'
end

def create_file_hash( file_path )
	#p file_path
	return Digest::SHA1.file( file_path ).hexdigest
end

def create_directory_hash( full_entry_list, directory_path, base_path )
	#p directory_path

	entries = ''
	Dir.entries( directory_path ).sort.each do |entry|

		entry_path = directory_path + entry;

		relative_path = Lace::Helpers.make_relative2( entry_path, base_path )

		if File.directory? entry_path
			next if entry == '.' || entry == '..' || entry == '.svn'

			entries += create_directory_hash( full_entry_list, entry_path, base_path ) + " #{relative_path.to_s}\n"
		else
			next if entry == blob_content_filename

			entries += create_file_hash( entry_path ) + " #{relative_path.to_s}\n"
		end
	end

	#puts entries
	full_entry_list << entries if full_entry_list

	return Digest::SHA1.hexdigest( entries )
end

def create_blob_directory_hash( directory_path )

	entries = ''
	dir_hash = create_directory_hash( entries, directory_path, directory_path )

	return dir_hash + " .\n" + entries
end

def write_blob_directory_hash_file( directory_path )

	entries = create_blob_directory_hash( directory_path )

	File.write( directory_path + blob_content_filename, entries )
end

module Lace
	class Blob
		def self.fetch( config, server_id, blob_path, required_hash )
			# check if the config is correct:
			raise "No Blob Servers configured!" if !config.blob_servers
			raise "No Blob Storage configured!" if !config.blob_local_path

			blob_servers = config.blob_servers
			blob_server = blob_servers[server_id]

			if !blob_server
				raise "Unknown blob server '#{server_id}'"
			end

			local_path = (config.blob_local_path + blob_server.directory + blob_path).expand_path
			blob_content_path = local_path + blob_content_filename()

			# check if the local path exists and if the hash file is present:
			if !File.exists?( blob_content_path )
				got_blob = false
				case blob_server.type
				when "svn"
				# check if the local path exists and if the hash file is present:
					svn_remote_path = blob_server.path + blob_path
					# no: export the svn path into the local path
					blob_dir = blob_content_path.dirname
					if File.exists?(blob_dir)
						# :TODO: remove the content?
						raise "Could not find blob hash file #{blob_content_path}" if !File.exists?( blob_content_path )
					else
						FileUtils.mkdir_p blob_dir.dirname
					end
					if blob_server.user
						svn_command_line = "svn --username #{blob_server.user} --password #{blob_server.password} --no-auth-cache export #{svn_remote_path} #{local_path}"
					else
						svn_command_line = "svn export #{svn_remote_path} #{local_path}"
					end
					puts "svn: exporting from #{svn_remote_path} into #{local_path}"
					#p "svn_command_line=#{svn_command_line}"
					result = system svn_command_line
					if !result
						raise "Could not get blob '#{blob_path}' from server '#{server_id} !"
					end
					puts "Creating Content Hash..."
					write_blob_directory_hash_file( local_path )
				when "local"
					# just return the local path:
				else
					raise "Invalid Blob storage type #{blob_server.type}"
				end
			end

			# check the content of the hash file:
			raise "Could not find blob hash file #{blob_content_path}" if !File.exists?( blob_content_path )

			blob_hash = File.new(blob_content_path).read(40)

			if blob_hash != required_hash
				raise "Invalid Blob Hash in blob #{blob_path} expected=#{required_hash} but got #{blob_hash}"
			end

			return local_path
		end
	end
end
