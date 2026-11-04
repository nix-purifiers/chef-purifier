require 'json'
require 'fileutils'
require 'chef-cli/cookbook_omnifetch'
require 'cookbook-omnifetch/artifactserver'

store = ENV.fetch('CHEF_PURIFIER_STORE')
FileUtils.mkdir_p(store)
Dir.children(ENV.fetch('CHEF_PURIFIER_DEPENDENCIES')).each do |name|
  destination = File.join(store, name)
  source = File.join(ENV.fetch('CHEF_PURIFIER_DEPENDENCIES'), name)
  if File.exist?(destination) || File.symlink?(destination)
    raise 'Locked cookbook alias changed' unless File.realpath(destination) == File.realpath(source)
  else
    File.symlink(source, destination)
  end
end
CookbookOmnifetch.configure do |configuration|
  configuration.cache_path = ENV.fetch('CHEF_PURIFIER_CACHE')
  configuration.storage_path = Pathname.new(store)
end
module PurifierFrozenCookbooks
  def install
    raise 'Cookbooks are Nix-resolved; use chef-purifier lock --update' unless installed?
  end
end
CookbookOmnifetch::ArtifactserverLocation.prepend(PurifierFrozenCookbooks)
require 'chef-cli/policyfile_services/export_repo'
module PurifierWritableExportMetadata
  def copy_unignored_cookbook_files(lock, export_path)
    super
    metadata = File.join(export_path, 'metadata.json')
    File.chmod(File.stat(metadata).mode | 0200, metadata) if File.exist?(metadata)
  end
end
ChefCLI::PolicyfileServices::ExportRepo.prepend(PurifierWritableExportMetadata)

if ENV['CHEF_PURIFIER_CONTEXT']
  require_relative 'project-model'
  context = JSON.parse(File.read(ENV.fetch('CHEF_PURIFIER_CONTEXT')))
  require_relative 'validate'
  ChefPurifierCookbooks.validate(context.fetch('remotes'), ENV.fetch('CHEF_PURIFIER_DEPENDENCIES'))
  current = ChefPurifierProject.read(context.fetch('project'))
  raise 'Policy dependency selection changed; use chef-purifier lock --update' unless current == context.fetch('selection')
  native = JSON.parse(File.read(File.join(context.fetch('project'), 'Policyfile.lock.json')))
  remote = native.fetch('cookbook_locks').reject { |_name, value| value.fetch('source_options').key?('path') }
  raise 'Native cookbook pins changed; use chef-purifier lock --update' unless remote == context.fetch('remotes')
end
if ENV['CHEF_PURIFIER_CONTEXT']
  require 'chef-cli/policyfile/community_cookbook_source'
  require 'chef-cli/command/update'
  module PurifierFrozenCatalog
    def full_community_graph
      context = JSON.parse(File.read(ENV.fetch('CHEF_PURIFIER_CONTEXT')))
      context.fetch('remotes').to_h do |name, entry|
        directory = File.join(ENV.fetch('CHEF_PURIFIER_DEPENDENCIES'), entry.fetch('cache_key'))
        loader = Chef::Cookbook::CookbookVersionLoader.new(directory)
        loader.load!
        metadata = loader.cookbook_version.metadata
        raise 'Cookbook gem dependencies require an additional provider' unless metadata.gems.empty?
        [name, {entry.fetch('version') => {'dependencies' => metadata.dependencies, 'download_url' => entry.fetch('origin')}}]
      end
    end
  end
  module PurifierFrozenUpdate
    def run(*args)
      warn 'Using locked Nix cookbook versions; use chef-purifier lock --update to refresh dependencies'
      super
    end
  end
  ChefCLI::Policyfile::CommunityCookbookSource.prepend(PurifierFrozenCatalog)
  ChefCLI::Command::Update.prepend(PurifierFrozenUpdate)
end
