require 'pxp-agent/test_helper.rb'

test_name 'C94777 - Ensure pxp-agent functions after agent host restart' do

  applicable_agents = agents.select { |agent| agent['platform'] !~ /aix/}
  unless applicable_agents then
    skip_test('All agent hosts are AIX and QENG-3629 prevents AIX hosts being restarted')
  end

  step 'Ensure each agent host has pxp-agent service running and enabled' do
    applicable_agents.each do |agent|
      on agent, puppet('resource service pxp-agent ensure=stopped')
      create_remote_file(agent, pxp_agent_config_file(agent), pxp_config_json_using_puppet_certs(master, agent).to_s)
      on agent, puppet('resource service pxp-agent ensure=running enable=true')
      show_pcp_logs_on_failure do
        assert(is_associated?(master, "pcp://#{agent}/agent"),
               "Agent #{agent} with PCP identity pcp://#{agent}/agent should be associated with pcp-broker")
      end
    end
  end

  step "restart each agent" do
    applicable_agents.each do |agent|
      agent.reboot
      assert(agent.up?, "Agent #{agent} should be up after reboot")
      on(agent, puppet('resource service pxp-agent ')) do |result|
        assert_match(/ensure => .running.,/, result.stdout,
                     "pxp-agent service should be running after reboot")
      end
      assert(is_associated?(master, "pcp://#{agent}/agent"),
                            "Agent #{agent} should be associated with pcp-broker following host reboot")
    end
  end

  step "Send an rpc_blocking_request to all agents after reboot" do
    target_identities = []
    applicable_agents.each do |agent|
      target_identities << "pcp://#{agent}/agent"
    end
    responses = nil # Declare here so scoped above the begin/rescue below
    begin
      responses = rpc_blocking_request(master, target_identities,
                                      'pxp-module-puppet', 'run',
                                      {:env => [], :flags => ['--noop',
                                                              '--onetime',
                                                              '--no-daemonize']
                                      })
    rescue => exception
      fail("Exception occurred when trying to run Puppet on all agents: #{exception.message}")
    end
    applicable_agents.each do |agent|
      step "Check Run Puppet response for #{agent}" do
        identity = "pcp://#{agent}/agent"
        response = responses[identity]
        assert(response.has_key?(:envelope), "Response from PCP for #{agent} is missing :envelope")
        assert(response[:envelope].has_key?(:message_type), "Response from PCP for #{agent} is missing "\
                                                            ":message_type in :envelope")
        assert_equal('http://puppetlabs.com/rpc_blocking_response',
                     response[:envelope][:message_type],
                     "Received a message from pcp-broker for #{agent} but it wasn't of "\
                     "type http://puppetlabs.com/rpc_blocking_response")
      end # Step for this agent
    end # iterating on each agent
  end # test step
end # test
