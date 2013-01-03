require 'git-process/sync'
require 'GitRepoHelper'
include GitProc

describe Sync do
  include GitRepoHelper

  before(:each) do
    create_files(%w(.gitignore))
    gitlib.commit('initial')
  end


  after(:each) do
    rm_rf(gitlib.workdir)
  end


  def log_level
    Logger::ERROR
  end


  def create_process(base = gitlib, opts = {})
    Sync.new(base, opts.merge({:rebase => false, :force => false}))
  end


  it "should work when pushing with fast-forward" do
    change_file_and_commit('a', '')

    gitlib.branch('fb', :base_branch => 'master')

    clone_repo('fb') do |gl|
      change_file_and_commit('a', 'hello', gl)
      gl.branches.include?('origin/fb').should be_true
      Sync.new(gl, :rebase => false, :force => false, :log_level => log_level).runner
      gl.branches.include?('origin/fb').should be_true
      gitlib.branches.include?('fb').should be_true
    end
  end


  it "should work with a different remote server name" do
    change_file_and_commit('a', '')

    gitlib.branch('fb', :base_branch => 'master')

    clone_repo('fb', 'a_remote') do |gl|
      change_file_and_commit('a', 'hello', gl)
      gl.branches.include?('a_remote/fb').should be_true
      Sync.new(gl, :rebase => false, :force => false, :log_level => log_level).runner
      gl.branches.include?('a_remote/fb').should be_true
      gitlib.branches.include?('fb').should be_true
    end
  end


  describe "when forcing the push" do

    def create_process(gitlib, opts)
      Sync.new(gitlib, opts.merge({:rebase => false, :force => true}))
    end


    it "should work when pushing with non-fast-forward" do
      change_file_and_commit('a', '')

      gitlib.branch('fb', :base_branch => 'master')

      clone_repo('fb') do |gl|
        gitlib.checkout('fb') do
          change_file_and_commit('a', 'hello', gitlib)
        end

        expect {
          Sync.new(gl, :rebase => false, :force => true, :log_level => log_level).runner
        }.to_not raise_error GitExecuteError
      end
    end

  end


  describe "when changes are made upstream" do

    def create_process(base, opts = {})
      Sync.new(base, opts.merge({:rebase => false, :force => false}))
    end


    it "should work when pushing with non-fast-forward by merging" do
      change_file_and_commit('a', '')

      gitlib.branch('fb', :base_branch => 'master')

      clone_repo('fb') do |gl|
        gitlib.checkout('fb') do
          change_file_and_commit('a', 'hello', gitlib)
        end

        expect {
          create_process(gl).runner
        }.to_not raise_error GitExecuteError
      end
    end

  end


  describe "when rebasing" do

    def create_process(gitlib, opts = {})
      Sync.new(gitlib, opts.merge({:rebase => true, :force => false}))
    end


    it "should work when pushing (non-fast-forward)" do
      change_file_and_commit('a', '')

      clone_repo do |gl|
        gl.checkout('fb', :new_branch => 'master')

        expect { create_process(gl).runner }.to_not raise_error GitExecuteError

        change_file_and_commit('a', 'hello', gitlib)

        expect { create_process(gl).runner }.to_not raise_error GitExecuteError
      end
    end


    it "should merge and then rebase if remote feature branch changed" do
      change_file_and_commit('a', '')

      gitlib.checkout('fb', :new_branch => 'master')

      clone_repo do |gl|
        gl.checkout('fb', :new_branch => 'origin/master')

        change_file_and_commit('b', 'hello', gl)
        change_file_and_commit('a', 'hello', gitlib)
        change_file_and_commit('b', 'goodbye', gl)
        change_file_and_commit('a', 'goodbye', gitlib)
        gitlib.checkout('master')

        expect { create_process(gl).runner }.to_not raise_error GitExecuteError
      end
    end

  end


  describe "when forcing local-only" do

    def create_process(dir, opts)
      Sync.new(dir, opts.merge({:rebase => true, :force => false, :local => true}))
    end


    it "should not try to push" do
      change_file_and_commit('a', '')

      gitlib.branch('fb', :base_branch => 'master')

      clone_repo('fb') do |gl|
        gitlib.checkout('fb')
        change_file_and_commit('a', 'hello', gitlib)

        sp = Sync.new(gl, :rebase => true, :force => false, :local => true, :log_level => log_level)
        gl.should_receive(:fetch) # want to get remote changes
        gl.should_not_receive(:push) # ...but not push any

        sp.runner
      end
    end

  end


  describe "when there is no remote" do

    def create_process(base, opts)
      Sync.new(base, opts.merge({:rebase => true, :force => false, :local => false}))
    end


    it "should not try to fetch or push" do
      change_file_and_commit('a', '')

      gitlib.branch('fb', :base_branch => 'master')

      sp = Sync.new(gitlib, :rebase => true, :force => false, :local => true, :log_level => log_level)
      gitlib.should_not_receive(:fetch)
      gitlib.should_not_receive(:push)

      sp.runner
    end

  end


  describe "when default rebase flag is used" do

    def create_process(base = gitlib, opts = {})
      Sync.new(base, opts.merge({:rebase => false, :force => false, :local => false}))
    end


    it "should try to rebase by flag" do
      change_file_and_commit('a', '', gitlib)

      gitlib.branch('fb', :base_branch => 'master')

      sp = Sync.new(gitlib, :rebase => true, :force => false, :local => true, :log_level => log_level)
      gitlib.should_receive(:rebase)
      gitlib.should_not_receive(:merge)

      sp.runner
    end


    it "should try to rebase by config" do
      change_file_and_commit('a', '', gitlib)

      gitlib.branch('fb', :base_branch => 'master')
      gitlib.config['gitProcess.defaultRebaseSync'] = 'true'

      sp = Sync.new(gitlib, :rebase => false, :force => false, :local => true, :log_level => log_level)
      gitlib.should_receive(:rebase)
      gitlib.should_not_receive(:merge)

      sp.runner
    end


    it "should not try to rebase by false config" do
      change_file_and_commit('a', '', gitlib)

      gitlib.branch('fb', :base_branch => 'master')
      gitlib.config['gitProcess.defaultRebaseSync'] = 'false'

      sp = Sync.new(gitlib, :rebase => false, :force => false, :local => true, :log_level => log_level)
      gitlib.should_not_receive(:rebase)
      gitlib.should_receive(:merge)

      sp.runner
    end


    it "should not try to rebase by false config" do
      change_file_and_commit('a', '', gitlib)

      gitlib.branch('fb', :base_branch => 'master')
      gitlib.config['gitProcess.defaultRebaseSync'] = 'false'

      sp = Sync.new(gitlib, :rebase => false, :force => false, :local => true, :log_level => log_level)
      gitlib.should_not_receive(:rebase)
      gitlib.should_receive(:merge)

      sp.runner
    end


    it "should try to rebase by true config" do
      change_file_and_commit('a', '', gitlib)

      gitlib.branch('fb', :base_branch => 'master')
      gitlib.config['gitProcess.defaultRebaseSync'] = 'true'

      sp = Sync.new(gitlib, :rebase => false, :force => false, :local => true, :log_level => log_level)
      gitlib.should_receive(:rebase)
      gitlib.should_not_receive(:merge)

      sp.runner
    end

  end


  it "should work with a different remote server name than 'origin'" do
    change_file_and_commit('a', '')

    gitlib.branch('fb', :base_branch => 'master')

    clone_repo('fb', 'a_remote') do |gl|
      change_file_and_commit('a', 'hello', gl)
      gl.branches.include?('a_remote/fb').should be_true

      Sync.new(gl, :rebase => false, :force => false, :log_level => log_level).runner

      gl.branches.include?('a_remote/fb').should be_true
      gitlib.branches.include?('fb').should be_true
    end
  end


  it 'should fail when removing current feature while on _parking_' do
    gitlib.checkout('_parking_', :new_branch => 'master')
    change_file_and_commit('a', '')

    expect { gitprocess.verify_preconditions }.to raise_error ParkedChangesError
  end

end
