require 'json'
require 'pathname'
require 'uri'
require 'chef-cli/policyfile_compiler'
require 'chef/cookbook/cookbook_version_loader'

module ChefPurifierProject
  def self.read(project)
    root = Pathname.new(project).realpath
    policy = root.join('Policyfile.rb')
    compiler = ChefCLI::PolicyfileCompiler.evaluate(File.read(policy), policy.to_s)
    compiler.error!
    raise 'Included policies require an additional provider' unless compiler.included_policies.empty?
    sources = compiler.dsl.default_source.map do |source|
      raise 'The initial provider supports public Supermarket sources' unless source.is_a?(ChefCLI::Policyfile::CommunityCookbookSource)
      uri = URI.parse(source.uri)
      raise 'Public HTTPS cookbook sources are required' unless uri.scheme == 'https' && !uri.userinfo && !uri.query && !uri.fragment
      {'uri' => source.uri, 'preferred' => source.preferred_cookbooks}
    end
    specs = compiler.cookbook_location_specs.transform_values do |spec|
      raise 'This cookbook source requires an additional provider' unless [nil, :path, :artifactserver].include?(spec.source_type)
      unknown = spec.source_options.keys - [:path, :artifactserver, :version]
      raise 'Custom cookbook source options require an additional provider' unless unknown.empty?
      {'constraint' => spec.version_constraint.to_s, 'options' => spec.source_options}
    end
    locals = compiler.cookbook_location_specs.filter_map do |name, spec|
      next unless spec.source_type == :path
      path = root.join(spec.source_options.fetch(:path)).realpath
      relative = path.relative_path_from(root).to_s
      raise 'Local cookbooks must be inside the working project' if relative == '..' || relative.start_with?('../')
      loader = Chef::Cookbook::CookbookVersionLoader.new(path.to_s)
      loader.load!
      metadata = loader.cookbook_version.metadata
      raise 'Cookbook gem dependencies require an additional provider' unless metadata.gems.empty?
      [name, {'path' => relative, 'dependencies' => metadata.dependencies}]
    end.to_h
    JSON.parse(JSON.generate({'sources' => sources, 'specifications' => specs, 'localCookbooks' => locals}))
  end
end
