require "spec_helper"
require "fileutils"
require "redis"
require "digest/sha1"

describe Bosh::Spec::IntegrationTest do

  BOSH_CONFIG   = File.expand_path("../assets/bosh_config.yml", __FILE__)
  BOSH_WORK_DIR = File.expand_path("../assets/bosh_work_dir", __FILE__)
  CLOUD_DIR     = "/tmp/bosh_test_cloud"
  CLI_DIR       = File.expand_path("../../cli", __FILE__)
  
  before(:all) do
    puts "Starting sandboxed environment for Bosh tests..."
    Bosh::Spec::Sandbox.start
  end

  after(:all) do
    puts "\nStopping sandboxed environment for Bosh tests..."
    Bosh::Spec::Sandbox.stop
  end

  def run_bosh(cmd)
    Dir.chdir(BOSH_WORK_DIR) do
      ENV["BUNDLE_GEMFILE"] = "#{CLI_DIR}/Gemfile"
      `#{CLI_DIR}/bin/bosh --config #{BOSH_CONFIG} #{cmd}`
    end
  end

  def format_output(out)
    out.gsub(/^\s*/, '').gsub(/\s*$/, '')    
  end

  def expect_output(cmd, expected_output)
    format_output(run_bosh(cmd)).should == format_output(expected_output)
  end

  before :each do
    Redis.new(:host => "localhost", :port => 63795).flushdb
    FileUtils.rm_rf(BOSH_CONFIG)
    FileUtils.rm_rf(CLOUD_DIR)
  end

  it "shows status" do
    expect_output("status", <<-OUT)
      Target:     not set
      User:       not set
      Deployment: not set
    OUT
  end

  it "sets and reads target" do
    expect_output("target http://nowhere.com", <<-OUT)
      Target set to 'http://nowhere.com'
    OUT

    expect_output("target", <<-OUT)
      Current target is 'http://nowhere.com'
    OUT
  end

  it "sets and reads existing deployment (also updating target in process)" do
    expect_output("deployment vmforce", <<-OUT)
      WARNING! Your target has been changed to 'http://vmforce-target:2560'
      Deployment set to 'vmforce'
    OUT

    expect_output("deployment", <<-OUT)
      Current deployment is 'vmforce'
    OUT

    expect_output("target", <<-OUT)
      Current target is 'http://vmforce-target:2560'
    OUT
  end

  it "unsets deployment when target is changed" do
    run_bosh("deployment 'vmforce'")
    expect_output("target somewhere", <<-OUT)
      WARNING! Your deployment has been unset
      Target set to 'somewhere'
    OUT
    expect_output("target", "Current target is 'somewhere'")
    expect_output("deployment", "Deployment not set")
  end

  it "keeps track of user associated with target" do
    run_bosh("target foo")
    run_bosh("login john pass")

    run_bosh("target bar")
    run_bosh("login jane pass")

    expect_output("status", <<-OUT)
      Target:     bar
      User:       jane
      Deployment: not set
    OUT

    run_bosh("target foo")
    expect_output("status", <<-OUT)
      Target:     foo
      User:       john
      Deployment: not set
    OUT
  end

  it "verifies a sample valid stemcell" do
    stemcell_filename = spec_asset("valid_stemcell.tgz")
    expect_output("stemcell verify #{stemcell_filename}", <<-OUT)
      Verifying stemcell...
      File exists and readable                                     OK
      Extract tarball                                              OK
      Manifest exists                                              OK
      Stemcell properties                                          OK
      Stemcell image file                                          OK
      '#{stemcell_filename}' is a valid stemcell
    OUT
  end

  it "points to an error when verifying an invalid stemcell" do
    stemcell_filename = spec_asset("stemcell_invalid_mf.tgz")
    expect_output("stemcell verify #{stemcell_filename}", <<-OUT)
      Verifying stemcell...
      File exists and readable                                     OK
      Extract tarball                                              OK
      Manifest exists                                              OK
      Stemcell properties                                          FAILED
      Stemcell image file                                          OK
      '#{stemcell_filename}' is not a valid stemcell:
      - Manifest should contain valid name, version and cloud properties
    OUT
  end

  it "verifies a sample valid release" do
    release_filename = spec_asset("valid_release.tgz")
    expect_output("release verify #{release_filename}", <<-OUT)
     Verifying release...
     File exists and readable                                     OK
     Extract tarball                                              OK
     Manifest exists                                              OK
     Release name/version                                         OK
     Read package 'stuff' (1 of 2)                                OK
     Package 'stuff' checksum                                     OK
     Read package 'mutator' (2 of 2)                              OK
     Package 'mutator' checksum                                   OK
     Read job 'cacher' (1 of 3)                                   OK
     Extract job 'cacher                                          OK
     Read job 'cacher' manifest                                   OK
     Check config 'file1.conf' for 'cacher'                       OK
     Check config 'file2.conf' for 'cacher'                       OK
     Job 'cacher' needs 'stuff' package                           OK
     Monit file for 'cacher'                                      OK
     Read job 'cleaner' (2 of 3)                                  OK
     Extract job 'cleaner                                         OK
     Read job 'cleaner' manifest                                  OK
     Job 'cleaner' needs 'stuff' package                          OK
     Job 'cleaner' needs 'mutator' package                        OK
     Monit file for 'cleaner'                                     OK
     Read job 'sweeper' (3 of 3)                                  OK
     Extract job 'sweeper                                         OK
     Read job 'sweeper' manifest                                  OK
     Check config 'test.conf' for 'sweeper'                       OK
     Job 'sweeper' needs 'mutator' package                        OK
     Monit file for 'sweeper'                                     OK
     '#{release_filename}' is a valid release
    OUT
  end

  it "points to an error on invalid release" do
    release_filename = spec_asset("release_invalid_checksum.tgz")
    expect_output("release verify #{release_filename}", <<-OUT)
     Verifying release...
     File exists and readable                                     OK
     Extract tarball                                              OK
     Manifest exists                                              OK
     Release name/version                                         OK
     Read package 'stuff' (1 of 2)                                OK
     Package 'stuff' checksum                                     FAILED
     Read package 'mutator' (2 of 2)                              OK
     Package 'mutator' checksum                                   FAILED
     Read job 'cacher' (1 of 3)                                   FAILED
     Read job 'sweeper' (2 of 3)                                  FAILED
     Read job 'tester' (3 of 3)                                   FAILED
     '#{release_filename}' is not a valid release:
     - Incorrect checksum for package 'stuff'
     - Incorrect checksum for package 'mutator'
     - Job 'cacher' not found
     - Job 'sweeper' not found
     - Job 'tester' not found
    OUT
  end

  it "asks to login if no user set and operation requires talking to director" do
    expect_output("user create john pass", <<-OUT)
      Please login first
    OUT
  end

  it "creates a user when correct target accessed" do
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    
    expect_output("user create john pass", <<-OUT)
      User john has been created
    OUT
  end

  it "can log in as a freshly created user and issue commands" do
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    run_bosh("user create jane pass")
    run_bosh("login jane pass")

    expect_output("user create tester testpass", <<-OUT)
      User tester has been created
    OUT
  end

  it "cannot log in if password is invalid" do
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    run_bosh("user create jane pass")
    run_bosh("login jane foo")
    
    expect_output("user create john pass", <<-OUT)
      Error 401: Authentication failed
    OUT
  end

  it "can upload a stemcell" do
    stemcell_filename = spec_asset("valid_stemcell.tgz")
    expected_id = Digest::SHA1.hexdigest("STEMCELL\n") # That's the contents of image file
    
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    out = run_bosh("stemcell upload #{stemcell_filename}")

    out.should =~ /Stemcell uploaded and created/
    File.exists?(CLOUD_DIR + "/stemcell_#{expected_id}").should be_true
  end

  it "can upload a release" do
    release_filename = spec_asset("valid_release.tgz")
    
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    out = run_bosh("release upload #{release_filename}")

    out.should =~ /Release uploaded and updated/
  end

  it "can't upload malformed release" do
    release_filename = spec_asset("release_invalid_checksum.tgz")
    
    run_bosh("target http://localhost:8085")
    run_bosh("login admin admin")
    out = run_bosh("release upload #{release_filename}")

    out.should =~ /Release is invalid, please fix, verify and upload again/
  end

  it "can deploy release" do
    pending
    #run_bosh("deployment test")
    #run_bosh("login admin admin")
  end

end