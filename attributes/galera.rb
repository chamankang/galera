include_attribute 'ktc-package::default'

default['galera']['mysql_tgz'] = 'mysql-5.5.23_wsrep_23.6-linux-x86_64.tar.gz'
default['galera']['uri'] = "http://#{node['repo_host']}/prod/kt/storage"
default['galera']['sst_method'] = 'mysqldump'
default['galera']['secure'] = 'yes'
