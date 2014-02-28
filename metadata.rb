name              'galera'
maintainer        'KT Cloudware'
maintainer_email  'wil.reichert@kt.com'
license           'All rights reserved'
description       'Installs/Configures Openstack Identity Service'
long_description  IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '0.5.4'

%w{ debian ubuntu centos fedora redhat }.each do |os|
  supports os
end

depends 'services'
