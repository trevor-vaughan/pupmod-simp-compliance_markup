#!/usr/bin/env ruby -S rspec
# vim: set expandtab ts=2 sw=2:
require 'spec_helper'
puppetver = SemanticPuppet::Version.parse(Puppet.version)
requiredver = SemanticPuppet::Version.parse("4.9.0")
puts puppetver
if (puppetver > requiredver)
  describe 'compliance_markup::hiera_backend' do
    context "when key doesn't exist in the compliance map" do
      let(:hieradata){ "test_spec" }
      it 'should throw an error' do
        errored = false
        ex = nil
        begin
          result = subject.execute("compliance_markup::test::nonexistent", {}, Puppet::Pops::Lookup::Context.new('rp_env', 'compliance_markup'))
        rescue Exception => e
          ex = e
          errored = true
        end
        expect(errored).to eql(true)
      end
      it 'should throw a :no_such_key error' do
        errored = false
        ex = nil
        begin
          result = subject.execute("compliance_markup::test::nonexistent", {}, Puppet::Pops::Lookup::Context.new('rp_env', 'compliance_markup'))
        rescue Exception => e
          ex = e
          errored = true
        end
        expect(ex.to_s).to match(/no_such_key/)
      end
    end
    context "when key does exist in the compliance map" do
      let(:hieradata){ "test_spec" }
      it 'should not throw an error' do
        errored = false
        ex = nil
        begin
          result = subject.execute("compliance_markup::test::testvariable", {}, Puppet::Pops::Lookup::Context.new('rp_env', 'compliance_markup'))
        rescue Exception => e
          ex = e
          errored = true
        end
        expect(errored).to eql(false)
      end
      it 'should not throw a :no_such_key error' do
        errored = false
        ex = nil
        begin
          result = subject.execute("compliance_markup::test::testvariable", {}, Puppet::Pops::Lookup::Context.new('rp_env', 'compliance_markup'))
        rescue Exception => e
          ex = e
          errored = true
        end
        expect(ex.to_s).to_not match(/no_such_key/)
      end
      it 'should return "disa"' do
        errored = false
        ex = nil
        begin
          result = subject.execute("compliance_markup::test::testvariable", {}, Puppet::Pops::Lookup::Context.new('rp_env', 'compliance_markup'))
        rescue Exception => e
          ex = e
          errored = true
        end
        expect(ex.to_s).to_not match(/no_such_key/)
      end
    end
  end
end
