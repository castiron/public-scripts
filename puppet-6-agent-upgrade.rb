require 'open3'

def run(cmd)
  puts cmd
  stdout, stderr, status = Open3.capture3(cmd)
  puts stdout
end

version_file = "/opt/puppetlabs/puppet/VERSION"
trash_dir = "/root/trash"
puppet_path = nil
if File.exists?("/usr/bin/puppet") puppet_path = "/usr/bin/puppet"
if File.exists?("/opt/puppetlabs/bin/puppet") puppet_path = "/opt/puppetlabs/bin/puppet"
  
version_file = "/opt/puppetlabs/puppet/VERSION"
v6_installed =  File.exists?(version_file) && File.read(version_file).start_with?("6.")

puts "-- Starting puppet 6 agent upgrade"

hostname = `hostname -f`
puts "-- Hostname: #{hostname}"

release_full = `lsb_release -a`
release = nil
release = "xenial" if release_full.include? "xenial"
release = "bionic" if release_full.include? "bionic"
raise "Release is not xenial or bionic" unless release
puts "-- Release: #{release}"

puts "-- Stopping old puppet"
run "#{puppet_path} resource service puppet ensure=stopped"

unless File.directory?(trash_dir)
  puts "  -- Making #{trash_dir}"
  Dir.mkdir(trash_dir)
end

if File.directory?("/etc/puppet")
  puts " -- Moving /etc/puppet to #{trash_dir}"
  run "mv /etc/puppet #{trash_dir}/"
end

unless v6_installed
  puts " -- Moving /etc/puppetlabs to #{trash_dir}"
  run "mv /etc/puppetlabs #{trash_dir}/"
end

unless v6_installed

  unless File.exists?("/root/puppet6-release-#{release}.deb") ||
         File.exists?("/etc/apt/sources.list.d/puppet6.list")
    run("cd /root && wget https://apt.puppetlabs.com/puppet6-release-#{release}.deb")
  end

  unless File.exists? "/etc/apt/sources.list.d/puppet6.list"
    puts "-- Adding puppet 6 apt repo"
    run("cd /root && dpkg -i puppet6-release-#{release}.deb")
    run("apt-get update")
  end

  if File.exists? "/root/puppet6-release-#{release}.deb"
    run("rm /root/puppet6-release-#{release}.deb")
  end

  stdout, stderr, status = Open3.capture3("apt -qq list puppet")
  if stdout.include?("installed")
    puts "-- Removing Puppet before installing v6"
    run("apt-get remove puppet -y")
  end
  
  puts "-- Installing puppet 6 agent"
  run("apt install puppet-agent -y")
  run("source /etc/profile.d/puppet-agent.sh")

else
  puts "-- Puppet6 already installed"
end

puppet_path = "/opt/puppetlabs/bin/puppet"
  
config =
  <<~HEREDOC
# This file can be used to override the default puppet settings.
# See the following links for more details on what settings are available:
# - https://puppet.com/docs/puppet/latest/config_important_settings.html
# - https://puppet.com/docs/puppet/latest/config_about_settings.html
# - https://puppet.com/docs/puppet/latest/config_file_main.html
# - https://puppet.com/docs/puppet/latest/configuration.html
[agent]
pluginsync      = true
report          = true
ignoreschedules = true
ca_server       = pancho-foreman.cichq.com
server          = pancho-foreman.cichq.com
certname        = #{hostname}
    HEREDOC

puts "-- Updating puppet agent configuration"
File.open("/etc/puppetlabs/puppet/puppet.conf", 'w') { |file| file.write(config) }

puts "-- Enabling puppet"
run "#{puppet_path} resource service puppet ensure=running"
