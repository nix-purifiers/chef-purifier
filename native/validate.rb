require 'chef-cli/cookbook_profiler/identifiers'
require 'chef/cookbook/cookbook_version_loader'
module ChefPurifierCookbooks
  def self.validate(remotes, root)
    remotes.each do |name, record|
      directory = File.join(root, record.fetch('cache_key'))
      loader = Chef::Cookbook::CookbookVersionLoader.new(directory)
      loader.load!
      cookbook = loader.cookbook_version
      identifier = ChefCLI::CookbookProfiler::Identifiers.new(cookbook)
      raise "Native cookbook identity changed: #{name}" unless identifier.content_identifier == record.fetch('identifier') && identifier.semver_version.to_s == record.fetch('version') && cookbook.metadata.name == name
      raise 'Cookbook gem dependencies require an additional provider' unless cookbook.metadata.gems.empty?
    end
  end
end
