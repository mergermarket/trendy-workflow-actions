require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'yaml'

class CodeartifactOnlyTest < Minitest::Test
  WORKFLOWS = {
    'build' => 'Build',
    'deploy' => 'Deploy'
  }.freeze

  def workflows
    WORKFLOWS.map do |file, job|
      workflow = YAML.load_file(File.join(__dir__, '..', '.github', 'workflows', "#{file}.yml"))
      [workflow, workflow.fetch('jobs').fetch(job).fetch('steps')]
    end
  end

  def validate(script, mode:, token:, npmrc: nil)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.npmrc'), npmrc) if npmrc
      _, _, status = Open3.capture3(
        { 'CODEARTIFACT_ONLY' => mode, 'NPM_ACCESS_TOKEN' => token },
        'bash', '-e', '-c', script, chdir: dir
      )
      status.success?
    end
  end

  def test_default_preserves_github_setup_and_opt_in_skips_it
    workflows.each do |workflow, steps|
      call = workflow.fetch(true).fetch('workflow_call')
      assert_equal false, call.fetch('inputs').fetch('codeartifact-only').fetch('default')
      assert_equal false, call.fetch('secrets').fetch('NPM_ACCESS_TOKEN').fetch('required')
      prepare = steps.find { |step| step['name'] == 'Prepare .npmrc' }
      assert_equal '${{ !inputs.codeartifact-only }}', prepare.fetch('if')
      login = steps.find { |step| step['name'] == 'Log in to CodeArtifact' }
      assert_equal '.npmrc', login.fetch('with').fetch('npmrc-path')
    end
  end

  def test_configuration_validation
    workflows.each do |_, steps|
      script = steps.find { |step| step['name'] == 'Validate npm configuration' }.fetch('run')
      assert validate(script, mode: 'false', token: 'example')
      refute validate(script, mode: 'false', token: '')
      assert validate(script, mode: 'true', token: '')
      assert validate(script, mode: 'true', token: '', npmrc: "registry=https://example.com/\n")
      refute validate(script, mode: 'true', token: '', npmrc: "@mergermarket:registry=https://example.com/\n")
      assert validate(script, mode: 'false', token: 'example', npmrc: "@mergermarket:registry=https://example.com/\n")
    end
  end
end
