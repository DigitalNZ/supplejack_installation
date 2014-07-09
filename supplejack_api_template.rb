# The Supplejack installation scripts are Crown copyright (C) 2014, New Zealand Government,
# and are licensed under the GNU General Public License, version 3. 
# See https://github.com/DigitalNZ/supplejack_installationn for details.
#
# Supplejack was created by DigitalNZ at the National Library of NZ
# and the Department of Internal Affairs. http://digitalnz.org/supplejack


require 'yaml'

# ------------------------------------------------------ 
# Check MongoDB connection
# ------------------------------------------------------
mongoid = `ps aux | grep [m]ongo | grep -v grep | awk '{ print $2 }'`

unless mongoid.present?
  raise 'Unable to connect to MongoDB. Make sure MongoDB is installed and runnung properly.'
end

# ------------------------------------------------------ 
# Install supplejack_api gem
# ------------------------------------------------------
gem 'supplejack_api', git: 'git@github.com:DigitalNZ/supplejack_api.git'

run 'bundle config build.nokogiri —use-system-libraries' # Prevent warning when building Nokogiri

run 'bundle install --quiet'


# Run the Supplejack API installer 
run 'bundle exec rails generate supplejack_api:install --force --no-documentation'
run 'bundle install --quiet'

# ------------------------------------------------------ 
# Start Solr
# ------------------------------------------------------
pids = `ps aux | grep [s]olr | grep -v grep | awk '{ print $2 }'`

if pids.present?
  pids = pids.split("\n")
  puts '------------------------------------------------------------------'
  puts "Found Solr instance running: #{pids.join(' ')}"
  pids.each do |pid|
    puts "- Killing #{pid}"
    Process.kill 2, pid.to_i
  end
  puts '------------------------------------------------------------------'
end

rake 'sunspot:solr:start'


# ------------------------------------------------------ 
# Generate API keys
# ------------------------------------------------------
api_key     = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')
manager_key = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')
worker_key  = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')


# ------------------------------------------------------ 
# Install Supplejack Manager
# ------------------------------------------------------
manager_settings = <<-SETTINGS
development: &development
  WORKER_HOST: "http://localhost:3002"
  WORKER_API_KEY: "#{worker_key}"
  HARVESTER_CACHING_ENABLED: true
  PARSER_TYPE_ENABLED: false
  API_HOST: "http://localhost:3000"
  API_MONGOID_HOSTS: "localhost:27017"

staging:
  <<: *development
SETTINGS

inside('tmp') do
  run 'git clone git@github.com:DigitalNZ/supplejack_manager.git --quiet'

  inside('supplejack_manager') do
    file 'config/application.yml', manager_settings, force: true
  end
  
  run 'mv supplejack_manager ../../'

  inside('../../supplejack_manager') do
    code = "User.new(email: 'test@example.com', name: 'Test User', password: 'password').update_attribute(:authentication_token, '#{manager_key}')"
    file 'db/seeds.rb', code, force: true
    run 'bundle install --quiet'
    run 'bundle exec rake db:seed'

    # ------------------------------------------------------ 
    # Run manager server
    # ------------------------------------------------------
    run 'bundle exec rails server -p3001 > /dev/null 2>&1 &'
  end
end


# ------------------------------------------------------ 
# Install Supplejack Worker
# ------------------------------------------------------
worker_settings = <<-SETTINGS
development:
  API_HOST: "http://localhost:3000"
  API_MONGOID_HOSTS: "localhost:27017"
  MANAGER_HOST: "http://localhost:3001"
  MANAGER_API_KEY: "#{manager_key}"
  HARVESTER_CACHING_ENABLED: true
  AIRBRAKE_API_KEY: "abc123"
  LINK_CHECKING_ENABLED: "true"
  LINKCHECKER_RECIPIENTS: "test@example.com"
SETTINGS

inside('tmp') do
  run 'git clone git@github.com:DigitalNZ/supplejack_worker.git --quiet'

  inside('supplejack_worker') do
    file 'config/application.yml', worker_settings, force: true
  end
  
  run 'mv supplejack_worker ../../'

  # ------------------------------------------------------ 
  # Run worker server
  # ------------------------------------------------------
  inside('../../supplejack_worker') do
    code = "User.create(authentication_token: '#{worker_key}')"
    file 'db/seeds.rb', code, force: true
    run 'bundle install --quiet'
    run 'bundle exec rake db:seed'

    run 'bundle exec rails server -p3002 > /dev/null 2>&1 &'

    run 'bundle exec sidekiq > /dev/null 2>&1 &'
  end
end

# ------------------------------------------------------ 
# Create Welcome page
# ------------------------------------------------------

route "get 'welcome', to: 'application#welcome'"

code = <<-CODE
class ApplicationController < ActionController::Base
  protect_from_forgery

  def welcome
  end
end
CODE

file 'app/controllers/application_controller.rb', code, force: true

file 'app/views/application/welcome.html.erb', <<-CODE
<div class="row">
  <div class"eight columns centered">
    <%
      api_key = SupplejackApi::User.last.authentication_token
    %>
    <h2>Congratulations!</h2>
    <h2>You now have a working Supplejack-powered API</h2>
  
    <h4>Your API key is <%= api_key %></h4>
  
    <h3>Accessing Supplejack</h3>
  
    <h5>To retrieve the sample record, go to:</h5>
    <a href="http://localhost:3000/records/<%= SupplejackApi::Record.last.record_id %>.json?api_key=<%= api_key %>">http://localhost:3000/records/<%= SupplejackApi::Record.last.record_id %>.json?api_key=<%= api_key %></a>
  
    <h5>To perform a search, go to:</h5>
    <a href="http://localhost:3000/records.json?api_key=<%= api_key %>">http://localhost:3000/records.json?api_key=<%= api_key %></a>
  
    <h5>To visit the Supplejack Manager go to:</h5>
    <p><a href="http://localhost:3001">http://localhost:3001/</a></p>
    <p>The default username/password is test@example.com/password</p>
  
    <h5>The Supplejack Worker go to:</h5>
    <p><a href="http://localhost:3002/harvest_jobs?auth_token=#{worker_key}.">http://localhost:3002/harvest_jobs?auth_token=#{worker_key}. </a></p>
  
    <p>Note, there is no data in the Worker yet.</p>
  
  
    <h3>What's Next?</h3>
    <ul>
      <li>Visit Supplejack documentation: http://digitalnz.github.io/supplejack</li>
      <li>Edit your schema file: http://digitalnz.github.io/supplejack/api/creating-a-schema.html</li>
      <li>Start creating records by installing the Supplejack <a href="http://digitalnz.github.io/supplejack/start/supplejack-manager.html">Manager</a> and <a href="http://digitalnz.github.io/supplejack/start/supplejack-worker.html">Worker</a></li>
    </ul>
  
    <h3>Developer Notes</h3>
  
    <p>To kill all rails servers, run the following:</p>
    <p><code>`ps -ef | grep '[p]300\|[s]idekiq' | awk '{ print $2; }' | while read line; do kill $line; done`</code></p>
  </div>
</div>
CODE

# ------------------------------------------------------ 
# Run API server
# ------------------------------------------------------
run 'bundle exec rails server -p3000 > /dev/null 2>&1 &'


# ------------------------------------------------------ 
# Generate API seed data
# ------------------------------------------------------
code = <<-CODE
  # Create user
  user = SupplejackApi::User.create(email: 'test@example.com', name: 'Test User', authentication_token: '#{api_key}', role: 'admin')

  # Create a sample record
  Sunspot.session = Sunspot::Rails.build_session
  record = SupplejackApi::Record.new(internal_identifier: 'abc123', status: 'active', landing_url: 'http://boost.co.nz/')
  record.fragments << SupplejackApi::Fragment.new(name: 'John Doe', address: 'Wellington, New Zealand')
  record.save!
  record.index!

  puts "\n"
  puts "\n"
  puts '------------------------------------------------------------------'
  puts 'Congratulations! You now have a working Supplejack-powered API'
  puts "\n"
  puts '############################################'
  puts '##  Your API key is ' + user.api_key  ##'
  puts '############################################'
  puts "\n"
  puts 'To retrieve the sample record, go to:'
  puts 'http://localhost:3000/records/' + record.record_id.to_s + '.json?api_key=' + user.api_key
  puts "\n"
  puts 'To perform a search, go to:'
  puts 'http://localhost:3000/records.json?api_key=' + user.api_key
  puts "\n"
  puts 'To visit the Supplejack Manager go to:'
  puts 'http://localhost:3001/. The default username/password is test@example.com/password'
  puts "\n"
  puts 'The Supplejack Worker go to:'
  puts 'http://localhost:3002/harvest_jobs?auth_token=#{worker_key}. Note, there is no data in the Worker yet.'
  puts "\n"
  puts "What's Next?"
  puts "------------"
  puts '* Visit Supplejack documentation: http://digitalnz.github.io/supplejack'
  puts '* Edit your schema file: http://digitalnz.github.io/supplejack/api/creating-a-schema.html'
  puts '* Start creating records by installing the Supplejack Manager and Worker'
  puts '  - Supplejack Manager: http://digitalnz.github.io/supplejack/start/supplejack-manager.html'
  puts '  - Supplejack Worker: http://digitalnz.github.io/supplejack/start/supplejack-worker.html'
  puts "\n"
  puts 'You can view all this information at any time by visiting:'
  puts 'http://localhost:3000/welcome'
  puts "\n"
  puts 'Developer Notes'
  puts "---------------"
  puts "To kill all rails servers, run the following: `ps -ef | grep '[p]300\|[s]idekiq' | awk '{ print $2; }' | while read line; do kill $line; done`"
  puts "\n"
  puts '------------------------------------------------------------------'
  puts "\n"
  puts "\n"
CODE

file 'db/seeds.rb', code, force: true
rake 'db:seed'
gsub_file('db/seeds.rb', /^\"|puts\s(.*)\s/, '', verbose: false)
