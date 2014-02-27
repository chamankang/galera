#
# Cookbook Name:: galera
# Recipe:: server
#
# rubocop:disable LineLength

include_recipe 'ktc-package'

install_flag = '/root/.galera_installed'

group 'mysql' do
end

user 'mysql' do
  gid 'mysql'
  comment 'MySQL server'
  system true
  shell '/bin/false'
end

remote_file "#{Chef::Config[:file_cache_path]}/#{node['galera']['mysql_tgz']}" do
  source "#{node['galera']['uri']}/#{node['galera']['mysql_tgz']}"
  action :create_if_missing
end

# strip .tar.gz
mysql_package = node['galera']['mysql_tgz'][0..-8]
bash 'install-mysql-package' do
  user 'root'
  code <<-EOH
    zcat #{Chef::Config[:file_cache_path]}/#{node['galera']['mysql_tgz']} | tar xf - -C #{node['mysql']['install_dir']}
    ln -sf #{node['mysql']['install_dir']}/#{mysql_package} #{node['mysql']['base_dir']}
  EOH
  not_if { File.directory?("#{node['mysql']['install_dir']}/#{mysql_package}") }
end

case node['platform']
when 'centos', 'redhat', 'fedora', 'suse', 'scientific', 'amazon'
  bash 'purge-mysql-galera' do
    user 'root'
    code <<-EOH
      killall -9 mysqld_safe mysqld &> /dev/null
      yum remove mysql mysql-libs mysql-devel mysql-server mysql-bench
      cd #{node['mysql']['data_dir']}
      [ $? -eq 0 ] && rm -rf #{node['mysql']['data_dir']}/*
      rm -rf /etc/my.cnf /etc/mysql
      rm -f /root/#{install_flag}
    EOH
    only_if { !FileTest.exists?(install_flag) }
  end
else
  bash 'purge-mysql-galera' do
    user 'root'
    code <<-EOH
      killall -9 mysqld_safe mysqld &> /dev/null
      apt-get -y remove --purge mysql-server mysql-client mysql-common
      apt-get -y autoremove
      apt-get -y autoclean
      cd #{node['mysql']['data_dir']}
      [ $? -eq 0 ] && rm -rf #{node['mysql']['data_dir']}/*
      cd #{node['mysql']['conf_dir']}
      [ $? -eq 0 ] && rm -rf #{node['mysql']['conf_dir']}/*
      rm -f /root/#{install_flag}
    EOH
    only_if { !FileTest.exists?(install_flag) }
  end
end

case node['platform']
when 'centos', 'redhat', 'fedora', 'suse', 'scientific', 'amazon'
  bash 'install-galera' do
    user 'root'
    code <<-EOH
      yum -y localinstall #{node['xtra']['packages']}
      yum -y install galera
    EOH
    not_if { FileTest.exists?(node['wsrep']['provider']) }
  end
else
  bash 'install-galera' do
    user 'root'
    code <<-EOH
      apt-get -y --force-yes install -o Dpkg::Options::="--force-confold" #{node['xtra']['packages']}
      apt-get -y --force-yes install -o Dpkg::Options::="--force-confold" galera
      apt-get -f install
    EOH
    not_if { FileTest.exists?(node['wsrep']['provider']) }
  end
end

directory node['mysql']['conf_dir'] do
  owner 'mysql'
  group 'mysql'
  mode '0755'
  action :create
  recursive true
end

directory node['mysql']['data_dir'] do
  owner 'mysql'
  group 'mysql'
  mode '0755'
  action :create
  recursive true
end

directory node['mysql']['run_dir'] do
  owner 'mysql'
  group 'mysql'
  mode '0755'
  action :create
  recursive true
end

# install db to the data directory
dd_cmd = "#{node['mysql']['base_dir']}/scripts/mysql_install_db "
dd_cmd << '--force --user=mysql '
dd_cmd << "--basedir=#{node['mysql']['base_dir']} "
dd_cmd << "--datadir=#{node['mysql']['data_dir']}"
execute 'setup-mysql-datadir' do
  command dd_cmd
  not_if { FileTest.exists?("#{node['mysql']['data_dir']}/mysql/user.frm") }
end

service_cmd = 'cp '
service_cmd << "#{node['mysql']['base_dir']}/support-files/mysql.server "
service_cmd << "/etc/init.d/#{node['mysql']['servicename']}"

execute 'setup-init.d-mysql-service' do
  command service_cmd
  not_if { FileTest.exists?(install_flag) }
end

init_host = false
mysql_service = Services::Service.new 'mysql'
hosts = mysql_service.members.map { |m| m.name }

wsrep_cluster_address = ''

# Assume that this mysql host has already been registered by ktc-database cook.
if hosts.length == 1 && hosts.first == node['fqdn']
  Chef::Log.info("I've got the galera init position.")
  init_host = true
  wsrep_cluster_address = 'gcomm://'
else
  hosts.each do |h|
    if h != node['fqdn']
      wsrep_cluster_address += "gcomm://#{h}:#{node['wsrep']['port']},"
    end
  end
  wsrep_cluster_address = wsrep_cluster_address[0..-2]
end

template 'my.cnf' do
  path "#{node['mysql']['conf_dir']}/my.cnf"
  source 'my.cnf.erb'
  owner 'mysql'
  group 'mysql'
  mode '0644'
  variables wsrep_urls: wsrep_cluster_address
  notifies :restart, 'service[mysql]', :immediately
end

bash 'wait-until-synced' do
  user 'root'
  code <<-EOH
    state=0
    cnt=0
    until [[ "$state" == "4" || "$cnt" > 5 ]]
    do
      state=$(#{node['galera']['mysql_bin']} -uroot -h127.0.0.1 -e "SET wsrep_on=0; SHOW GLOBAL STATUS LIKE 'wsrep_local_state'")
      state=$(echo "$state"  | tr '\n' ' ' | awk '{print $4}')
      cnt=$(($cnt + 1))
      sleep 1
    done
  EOH
  only_if { init_host && !FileTest.exists?(install_flag) }
end

bash 'set-wsrep-grants-mysqldump' do
  user 'root'
  code <<-EOH
    #{node['galera']['mysql_bin']} -uroot -h127.0.0.1 -e "GRANT ALL ON *.* TO '#{node['wsrep']['user']}'@'%' IDENTIFIED BY '#{node['wsrep']['password']}'"
    #{node['galera']['mysql_bin']} -uroot -h127.0.0.1 -e "SET wsrep_on=0; GRANT ALL ON *.* TO '#{node['wsrep']['user']}'@'127.0.0.1' IDENTIFIED BY '#{node['wsrep']['password']}'"
  EOH
  only_if do
    init_host && (node['galera']['sst_method'] == 'mysqldump') &&
      !FileTest.exists?(install_flag)
  end
end

bash 'secure-mysql' do
  user 'root'
  code <<-EOH
    #{node['galera']['mysql_bin']} -uroot -h127.0.0.1 -e "DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE DB='test' OR DB='test\\_%'"
    #{node['galera']['mysql_bin']} -uroot -h127.0.0.1 -e "UPDATE mysql.user SET Password=PASSWORD('#{node['mysql']['server_root_password']}') WHERE User='root'; DELETE FROM mysql.user WHERE User=''; DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1'); GRANT ALL ON *.* TO 'root'@'%' IDENTIFIED BY '#{node['mysql']['server_root_password']}' WITH GRANT OPTION; FLUSH PRIVILEGES;"
  EOH
  only_if do
    init_host && (node['galera']['secure'] == 'yes') &&
      !FileTest.exists?(install_flag)
  end
end

service 'mysql' do
  supports restart: true, start: true, stop: true
  service_name node['mysql']['servicename']
  action :enable
end

execute 'galera-installed' do
  command "touch #{install_flag}"
  action :run
  not_if { FileTest.exists?(install_flag) }
end
