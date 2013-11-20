#
# Cookbook Name:: ktc-database
# Recipe:: default
#
# Copyright 2013, KT Cloudware
#
# All rights reserved - Do Not Redistribute
#

include_recipe "services"
include_recipe "ktc-utils"

iface = KTC::Network.if_lookup "management"
ip = KTC::Network.address "management"

Services::Connection.new run_context: run_context
member = Services::Member.new node.fqdn,
  service: "mysql",
  port: 3306,
  proto: "tcp",
  ip: ip
member.save

node.default["openstack"]["db"]["bind_interface"] = iface

include_recipe "ktc-openstack-ha::mysql"
include_recipe "galera::server"
