name 'purifier-proof'
default_source :supermarket
run_list 'purifier-fixture::default'
cookbook 'purifier-fixture', path: 'cookbooks/purifier-fixture'
