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
gem 'supplejack_api', git: 'https://github.com/DigitalNZ/supplejack_api.git', branch: 'oliver/install-bugs'
gem 'jquery-rails'

run 'bundle config build.nokogiri —use-system-libraries' # Prevent warning when building Nokogiri

puts 'Bundling your api....'
run 'bundle install --quiet'

puts 'Running supplejack_api generator install script'
# Run the Supplejack API installer
run 'bundle exec rails generate supplejack_api:install --force --no-documentation'
run 'bundle install --quiet'

# ------------------------------------------------------
# Start Solr
# ------------------------------------------------------

puts 'Attempting to start solr'
code = <<-CODE
development:
  solr:
    hostname: 127.0.0.1
    port: 8982
    log_level: INFO
    path: /solr/development
CODE

file 'config/sunspot.yml', code, force: true
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

puts 'Sleeping for 15 seconds because sunspot is can be slow to wake up in the morning...'
sleep 15

# ------------------------------------------------------
# Start Sidekiq
# ------------------------------------------------------
puts 'Attempting to sidekiq'
sidekiq_pid = `ps aux | grep sidekiq | grep -v grep | awk '{ print $2 }'`

if sidekiq_pid.present?
  puts '------------------------------------------------------------------'
  puts "Found Sidekiq instance running: #{sidekiq_pid}"
  puts "Killing #{sidekiq_pid}"
  Process.kill 2, sidekiq_pid.to_i
end

run "bundle exec sidekiq > /dev/null 2>&1 &"

# ------------------------------------------------------
# Generate API keys
# ------------------------------------------------------
manager_key     = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')
harvester_key = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')
worker_key  = SecureRandom.urlsafe_base64(15).tr('lIO0', 'sxyz')



# ------------------------------------------------------
# Generate API seed record data
# ------------------------------------------------------
puts 'Seeding API data'
code = <<-RUBY
  # Create user
  user = SupplejackApi::User.create(
    email: 'manager_key@example.com',
    name: 'Manager Key User',
    password: 'password',
    role: 'admin',
    authentication_token: "#{manager_key}")
  # Create harvester
  harvester = SupplejackApi::User.create(
    email: 'harvester_key@example.com',
    name: 'Api Key User',
    password: 'password',
    role: 'harvester',
    authentication_token: "#{harvester_key}")

  # Create a sample record
  Sunspot.session = Sunspot::Rails.build_session
  record = SupplejackApi::Record.new(
    internal_identifier: 'abc123',
    status: 'active',
    landing_url: 'http://boost.co.nz/')

  # Attach fragments
  record.fragments << SupplejackApi::ApiRecord::RecordFragment.new(
    title: 'Supplejack API',
    description: 'The Supplejack API is a mountable engine which provides functionality to store, index and retrieve metadata via an API.',
    category: ['engine'],
    display_content_partner: 'DigitalNZ',
    display_collection: 'natlib.govt.nz',
    source_url: 'http://natlib.govt.nz')

  # Save and index
  record.save!
  record.index!
RUBY

file 'db/seeds.rb', code, force: true
rake 'db:seed --trace'
gsub_file('db/seeds.rb', /^\"|puts\s(.*)\s/, '', verbose: false)

puts 'Seeded API data'

# ------------------------------------------------------
# Install Supplejack Manager
# ------------------------------------------------------
puts 'Installing Supplejack Manager'
if yes?("Do you want to enable concept harvest?")
  concept_enabled = true
else
  concept_enabled = false
end
manager_settings = <<-SETTINGS
development: &development
  WORKER_HOST: "http://localhost:3002"
  WORKER_KEY: "#{worker_key}"
  HARVESTER_API_KEY: "#{harvester_key}"
  HARVESTER_CACHING_ENABLED: true
  PARSER_TYPE_ENABLED: #{concept_enabled}
  API_HOST: "http://localhost:3000"
  API_MONGOID_HOSTS: "localhost:27017"

staging:
  <<: *development
SETTINGS

inside('tmp') do
  run 'git clone https://github.com/DigitalNZ/supplejack_manager.git --quiet'

  inside('supplejack_manager') do
    file 'config/application.yml', manager_settings, force: true
  end

  run 'mv supplejack_manager ../../'

  inside('../../supplejack_manager') do
    code = "User.new(email: 'test@example.com', name: 'Test User', password: 'password', role: 'admin').update_attribute(:authentication_token, '#{manager_key}')"
    file 'db/seeds.rb', code, force: true
    run 'bundle install --quiet'
    run 'bundle exec rake db:seed'

    # ------------------------------------------------------
    # Run manager server
    # ------------------------------------------------------
    # run 'bundle exec rails server -p3001 > /dev/null 2>&1 &'
  end
end


# ------------------------------------------------------
# Install Supplejack Worker
# ------------------------------------------------------
puts 'Installing Supplejack Worker'
worker_settings = <<-SETTINGS
development:
  API_HOST: "http://localhost:3000"
  API_MONGOID_HOSTS: "localhost:27017"
  MANAGER_HOST: "http://localhost:3001"
  HARVESTER_CACHING_ENABLED: true
  AIRBRAKE_API_KEY: "abc123"
  LINK_CHECKING_ENABLED: "true"
  LINKCHECKER_RECIPIENTS: "test@example.com"
  HARVESTER_API_KEY: "#{manager_key}"
  WORKER_KEY: "#{worker_key}"
SETTINGS

inside('tmp') do
  run 'git clone https://github.com/DigitalNZ/supplejack_worker.git --quiet'

  inside('supplejack_worker') do
    file 'config/application.yml', worker_settings, force: true
  end

  run 'mv supplejack_worker ../../'

  # ------------------------------------------------------
  # Run worker server
  # ------------------------------------------------------
  inside('../../supplejack_worker') do
    run 'bundle install --quiet'
    run 'bundle exec rake db:seed'

    # run 'bundle exec rails server -p3002 > /dev/null 2>&1 &'

    run 'bundle exec sidekiq > /dev/null 2>&1 &'
  end
end

# ------------------------------------------------------
# Create Welcome page
# ------------------------------------------------------

route "get 'welcome', to: 'application#welcome'"

code = <<-RUBY
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception

  def welcome
  end
end
RUBY

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

    <h5>To visit the Supplejack Manager</h5>
    <p>In your terminal, change directory to supplejack_manager, and run 'bundle exec rails s -p 3001'</p>
    <p>Then visit: <a href="http://localhost:3001">http://localhost:3001/</a></p>
    <p>The default username/password is test@example.com/password</p>

    <h5>The Supplejack Worker</h5>
    <p>In your terminal, change directory to supplejack_worker, and run 'bundle exec rails s -p 3002'</p>

    <p>Then visit: <a href="http://localhost:3002/harvest_jobs?auth_token=#{worker_key}.">http://localhost:3002/harvest_jobs?auth_token=#{worker_key}. </a></p>

    <p>Note, there is no data in the Worker yet.</p>


    <h3>What's Next?</h3>
    <ul>
      <li>Visit Supplejack documentation: http://digitalnz.github.io/supplejack</li>
      <li>Edit your schema file: http://digitalnz.github.io/supplejack/api/creating-a-schema.html</li>
      <li>Start creating records by installing the Supplejack <a href="http://digitalnz.github.io/supplejack/start/supplejack-manager.html">Manager</a> and <a href="http://digitalnz.github.io/supplejack/start/supplejack-worker.html">Worker</a></li>
      <li>Clone Supplejack Website demo and start interacting with your API. Visit <a href="http://digitalnz.github.io/supplejack/start/supplejack-website.html">Supplejack Website Demo</a> for more info</li>
    </ul>

    <h3>Developer Notes</h3>

    <p>To kill all rails servers, run the following:</p>
    <p><code>`ps -ef | grep '[p]300\|[s]idekiq' | awk '{ print $2; }' | while read line; do kill $line; done`</code></p>
  </div>
</div>
CODE

# ------------------------------------------------------
# Contratulations and start up instructions.
# ------------------------------------------------------
puts "\n"
puts "\n"
puts '------------------------------------------------------------------'
puts 'Congratulations! You now have a working Supplejack-powered API'
puts "\n"
puts '############################################'
puts '##  Your API key is ' + manager_key
puts '############################################'
puts "\n"
puts "To start your api application, cd in to your application and run 'bundle exec rails s -p 3000'"
puts "\n"
puts 'To perform a search, go to:'
puts 'http://localhost:3000/records.json?api_key=' + manager_key
puts "\n"
puts 'To retrieve the sample record, use the id of one of the records from your search, and go to:'
puts 'http://localhost:3000/records/<record_id here>.json?api_key=' + manager_key
puts "\n"
puts "For example: http://localhost:3000/records/5.json?api_key=" + manager_key
puts "\n"
puts "What's Next?"
puts "------------"
puts '* Visit Supplejack documentation: http://digitalnz.github.io/supplejack'
puts '* Edit your schema file: http://digitalnz.github.io/supplejack/api/creating-a-schema.html'
puts '* Start creating records by installing the Supplejack Manager and Worker'
puts '  - Supplejack Manager: http://digitalnz.github.io/supplejack/start/supplejack-manager.html'
puts '  - Supplejack Worker: http://digitalnz.github.io/supplejack/start/supplejack-worker.html'
puts '* Clone Supplejack Website demo and start interacting with your API. http://digitalnz.github.io/supplejack/start/supplejack-website.html'
puts "\n"
puts 'You can view all this information at any time by visiting:'
puts 'http://localhost:3000/welcome'
puts "\n"
