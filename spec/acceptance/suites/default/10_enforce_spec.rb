require 'spec_helper_acceptance'
require 'semantic_puppet'
test_name 'compliance_markup class enforcement'

describe 'compliance_markup class enforcement' do
  let(:base_manifest) {
    <<-EOS
      include 'useradd'
    EOS
  }

  let(:base_hieradata) {{
    'compliance_markup::enforcement'    => ['disa'],
    'compliance_markup::compliance_map' => {
      'version' => '1.0.0',
      'disa'    => {
        'useradd::shells' => {
          'identifiers' => ['FOO2','BAR2'],
          'notes'       => 'Nothing fun really',
          'value'       => ['/bin/disa']
        }
      },
      'nist'    => {
        'useradd::shells' => {
          'identifiers' => ['FOO2','BAR2'],
          'notes'       => 'Nothing fun really',
          'value'       => ['/bin/nist']
        }
      }
    }
  }}

  let(:extra_hieradata) {{
    'compliance_markup::enforcement'    => ['nist','disa'],
    'compliance_markup::compliance_map' => {
      'version' => '1.0.0',
      'disa'    => {
        'useradd::shells' => {
          'identifiers' => ['FOO2','BAR2'],
          'notes'       => 'Nothing fun really',
          'value'       => ['/bin/disa']
        }
      },
      'nist'    => {
        'useradd::shells' => {
          'identifiers' => ['FOO2','BAR2'],
          'notes'       => 'Nothing fun really',
          'value'       => ['/bin/nist']
        }
      }
    }
  }}

  let (:v5_hiera_yaml) { File.read('spec/acceptance/suites/default/files/hiera_v5.yaml') }

  hosts.each do |host|
    puppetver   = SemanticPuppet::Version.parse(ENV.fetch('PUPPET_VERSION', '4.10.4'))
    requiredver = SemanticPuppet::Version.parse("4.9.0")
    if (puppetver > requiredver)
      versions = [ 'v5' ]
    else
      fail("Only puppet > #{requiredver} is supported moving forward")
    end

    versions.each do |version|
      context "with a #{version} hiera.yaml" do
        context 'with a single compliance map' do
          case version
          when 'v5'
            let (:hiera_yaml) { v5_hiera_yaml }
          end

          it 'should work with no errors' do
            create_remote_file(host, '/etc/puppetlabs/puppet/hiera.yaml', hiera_yaml)
            set_hieradata_on(host, base_hieradata)
            apply_manifest_on(host, base_manifest, :catch_failures => true)
          end

          it 'should be idempotent' do
            apply_manifest_on(host, base_manifest, :catch_changes => true)
          end

          it 'should have /bin/sh in /etc/shells' do
            apply_manifest_on(host, base_manifest, :catch_failures => true)
            result = on(host, 'cat /etc/shells').output.strip
            expect(result).to match(%r(/bin/sh))
          end

          context 'when disa is higher priority' do
            it 'should have /bin/disa in /etc/shells' do
              create_remote_file(host, '/etc/puppetlabs/puppet/hiera.yaml', hiera_yaml)
              set_hieradata_on(host, base_hieradata)

              apply_manifest_on(host, base_manifest, :catch_failures => true)

              result = on(host, 'cat /etc/shells').output.strip
              expect(result).to match(%r(/bin/disa))
              expect(result).to_not match(%r(/bin/nist))
            end
          end

          context 'when nist is higher priority' do
            it 'should have /bin/nist in /etc/shells' do
              create_remote_file(host, '/etc/puppetlabs/puppet/hiera.yaml', hiera_yaml)
              set_hieradata_on(host, extra_hieradata)

              apply_manifest_on(host, base_manifest, :catch_failures => true)

              result = on(host, 'cat /etc/shells').output.strip
              expect(result).to match(%r(/bin/nist))
              expect(result).to_not match(%r(/bin/disa))
            end
          end
        end
      end
    end
  end
end
