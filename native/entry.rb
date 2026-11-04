case ENV['CHEF_PURIFIER_MODE']
when 'project'
  require_relative 'project-model'
  File.write(ENV.fetch('CHEF_PURIFIER_MODEL'), JSON.generate(ChefPurifierProject.read(ENV.fetch('CHEF_PURIFIER_PROJECT'))))
  exit
when 'verify-project'
  require_relative 'project-model'
  manifest = JSON.parse(File.read(ENV.fetch('CHEF_PURIFIER_MANIFEST')))
  current = ChefPurifierProject.read(ENV.fetch('CHEF_PURIFIER_PROJECT'))
  raise 'Policy dependencies changed; run chef-purifier lock --update' unless current == manifest.fetch('selection')
  exit
when 'validate'
  require 'json'
  require_relative 'validate'
  manifest = JSON.parse(File.read(ENV.fetch('CHEF_PURIFIER_MANIFEST')))
  ChefPurifierCookbooks.validate(manifest.fetch('remotes'), ENV.fetch('CHEF_PURIFIER_DEPENDENCIES'))
  exit
when 'replay'
  require_relative 'replay'
when 'frozen'
  require_relative 'runtime'
end
