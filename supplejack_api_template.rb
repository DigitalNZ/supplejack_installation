# The Supplejack code is Crown copyright (C) 2014, New Zealand Government,
# and is licensed under the GNU General Public License, version 3. 
# See https://github.com/DigitalNZ/supplejack for details. 
#
# Supplejack was created by DigitalNZ at the National Library of NZ 
# and the Department of Internal Affairs. http://digitalnz.org/supplejack

require 'yaml'
require 'devise'

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
gem 'supplejack_api', git: 'https://github.com/DigitalNZ/supplejack_api.git'
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
api_key = Devise.friendly_token
manager_key = Devise.friendly_token
worker_key = Devise.friendly_token


# ------------------------------------------------------ 
# Install Supplejack Manager
# ------------------------------------------------------
manager_settings = <<-SETTINGS
development: &development
  WORKER_HOST: "http://localhost:3002"
  WORKER_API_KEY: "#{worker_key}"
  HARVESTER_CACHING_ENABLED: true
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
    run 'bundle exec rake db:seed'

    # ------------------------------------------------------ 
    # Run manager server
    # ------------------------------------------------------
    run 'bundle exec rails server -p3001 &'
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
    run 'bundle exec rake db:seed'

    run 'bundle exec rails server -p3002 &'

    run 'bundle exec sidekiq &'
  end
end


# ------------------------------------------------------ 
# Run API server
# ------------------------------------------------------
run 'bundle exec rails server -p3000 &'


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
  puts 'Your API key is ' + user.api_key
  puts "\n"
  puts 'To retrieve the sample record, go to:'
  puts 'http://localhost:3000/records/' + record.record_id.to_s + '.json?api_key=' + user.api_key
  puts "\n"
  puts 'To perform a search, go to:'
  puts 'http://localhost:3000/records.json?api_key=' + user.api_key
  puts "\n"
  puts 'To visit the SuppleJack Manger go to:'
  puts 'http://localhost:3001/. The default username/password is test@example.com/password'
  puts "\n"
  puts 'The SuppleJack Worker go to:'
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
  puts 'Developer Notes'
  puts "---------------"
  puts "To kill all rails servers, run the following: `ps -ef | grep '[p]300' | awk '{ print $2; }' | while read line; do kill $line; done`"
  puts "\n"
  puts '------------------------------------------------------------------'
  puts "\n"
  puts "\n"
CODE

file 'db/seeds.rb', code, force: true
rake 'db:seed'
gsub_file('db/seeds.rb', /^\"|puts\s(.*)\s/, '')
