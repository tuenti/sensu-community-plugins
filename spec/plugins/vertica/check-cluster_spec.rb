#! /usr/bin/env ruby
#
#   check-cluster_spec
#
# DESCRIPTION:
#
# OUTPUT:
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: check-cluster
#
# USAGE:
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require_relative '../../../plugins/vertica/check-cluster'
require_relative '../../../spec_helper'

describe CheckVerticaCluster, 'run' do

  it 'returns ok if all nodes are in UP state' do
  end

  it 'returns warning if any of the nodes are in INITIALIZING, SHUTDOWN or RECOVERING state' do
  end

  it 'returns critical if at least one node is in DOWN state' do
  end
end

