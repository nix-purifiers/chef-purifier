require 'json'
require 'tempfile'
require 'fileutils'
require 'chef-cli/cookbook_omnifetch'
require 'cookbook-omnifetch/artifactserver'

CookbookOmnifetch.configure do |configuration|
  configuration.cache_path = ENV.fetch('CHEF_PURIFIER_CACHE')
  configuration.storage_path = Pathname.new(ENV.fetch('CHEF_PURIFIER_STORE'))
end
module PurifierArchiveReplay
  class FileHTTP
    def initialize(path)
      @path = path
    end
    def streaming_request(_request)
      Tempfile.create('cinc-native-archive') do |file|
        FileUtils.copy_file(@path, file.path)
        yield file
      end
    end
  end
  def http_client(uri)
    archives = JSON.parse(File.read(ENV.fetch('CHEF_PURIFIER_ARCHIVES')))
    path = archives.fetch(uri.to_s) { raise "Uncaptured native cookbook source #{uri}" }
    FileHTTP.new(path)
  end
end
CookbookOmnifetch::ArtifactserverLocation.prepend(PurifierArchiveReplay)
