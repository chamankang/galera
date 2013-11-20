name             'ktc-galera'
maintainer       'KT Cloudware'
maintainer_email 'wil.reichert@kt.com'
license          'All rights reserved'
description      'Application / role cookbook for stackforge os-ops-database cookbook'
version          '0.0.1'

%w{ centos ubuntu }.each do |os|
  supports os
end

depends "galera"
depends "ktc-utils"
depends "ktc-openstack-ha"
depends "services"
