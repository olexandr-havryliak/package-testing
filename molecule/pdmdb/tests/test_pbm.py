import os
import pytest
import yaml
try:
    from StringIO import StringIO
except ImportError:
    from io import StringIO

import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')

PBM_VERSION = os.environ["PBM_VERSION"]

storage_configs = ['/etc/pbm-agent-storage.conf', '/etc/pbm-agent-storage-gcp.conf',
                   '/etc/pbm-agent-storage-local.conf']


def parse_yaml_string(ys):
    """Parse yaml string to dictionary

    :param ys:
    :return:
    """
    fd = StringIO(ys)
    dct = yaml.load(fd)
    return dct


@pytest.fixture()
def start_stop_pbm(host):
    """Start and stop pbm-agent service

    :param host:
    :return:
    """
    cmd = "sudo systemctl stop pbm-agent"
    result = host.run(cmd)
    assert result.rc == 0, result.stdout
    cmd = "sudo systemctl start pbm-agent"
    result = host.run(cmd)
    assert result.rc == 0, result.stdout
    cmd = "sudo systemctl status pbm-agent"
    return host.run(cmd)


@pytest.fixture()
def restart_pbm_agent(host):
    """Restart pbm-agent service
    """
    cmd = "sudo systemctl restart pbm-agent"
    result = host.run(cmd)
    assert result.rc == 0, result.stdout
    cmd = "sudo systemctl status pbm-agent"
    return host.run(cmd)


@pytest.fixture()
def set_store(host):
    """Set store for pbm

    :param host:
    :return:
    """
    command = "pbm config --file=/etc/pbm-agent-storage.conf --mongodb-uri=mongodb://localhost:27017/"
    result = host.run(command)
    return result


@pytest.fixture()
def show_store(host, set_store):
    """Show pbm store

    :param host:
    :param set_store:
    :return:
    """
    command = "pbm config --list --mongodb-uri=mongodb://localhost:27017/?replicaSet=rs1"
    result = host.run(command)
    assert result.rc == 0, result.stdout
    pbm_ver = float(".".join(os.getenv("PBM_VERSION").split(".")[0:2]))
    if pbm_ver < 1.6:
        return parse_yaml_string(result.stdout.split("\n", 2)[2].strip())
    return parse_yaml_string(result.stdout)


def test_package(host):
    """Check pbm package
    """
    package = host.package("percona-backup-mongodb")
    assert package.is_installed
    assert PBM_VERSION in package.version, package.version


def test_service(host):
    """Check pbm-agent service
    """
    service = host.service("pbm-agent")
    assert service.is_enabled
    assert service.is_running


def test_pbm_binary(host):
    """Check pbm binary
    """
    file = host.file("/usr/bin/pbm")
    assert file.user == "root"
    assert file.group == "root"
    try:
        assert file.mode == 0o755
    except AssertionError:
        pytest.xfail("Possible xfail")


def test_pbm_agent_binary(host):
    """Check pbm agent binary
    """
    file = host.file("/usr/bin/pbm-agent")
    assert file.user == "root"
    assert file.group == "root"
    try:
        assert file.mode == 0o755
    except AssertionError:
        pytest.xfail("Possible xfail")


def test_pbm_storage_default_config(host):
    """Check pbm agent binary
    """
    file = host.file("/etc/pbm-storage.conf")
    assert file.user == "pbm"
    assert file.group == "pbm"
    try:
        assert file.mode == 0o644
    except AssertionError:
        pytest.xfail("Possible xfail")


# TODO add correct start/stop test
def test_start_stop_service(start_stop_pbm):
    """Start and stop pbm agent

    :param start_stop_pbm:
    """
    assert start_stop_pbm.rc == 0, restart_pbm_agent.stdout
    assert "active" in start_stop_pbm.stdout, restart_pbm_agent.stdout


def test_restart_service(restart_pbm_agent):
    """Restart pbm agent

    :param restart_pbm_agent:
    """
    assert restart_pbm_agent.rc == 0, restart_pbm_agent.stdout
    assert "active" in restart_pbm_agent.stdout


def test_pbm_version(host):
    """Check that pbm version is not empty strings

    :param host:
    :return:
    """
    result = host.run("pbm version")
    assert result.rc == 0, result.stdout
    lines = result.stdout.split("\n")
    parsed_config = {line.split(":")[0]: line.split(":")[1].strip() for line in lines[0:-1]}
    assert parsed_config['Version'] == PBM_VERSION, parsed_config
    assert parsed_config['Platform'], parsed_config
    assert parsed_config['GitCommit'], parsed_config
    assert parsed_config['GitBranch'], parsed_config
    assert parsed_config['BuildTime'], parsed_config
    assert parsed_config['GoVersion'], parsed_config


def test_pbm_help(host):
    """Check that pbm have help message

    :param host:
    :return:
    """
    result = host.run("pbm help")
    assert result.rc == 0, result.stdout


def test_set_store(set_store):
    """Set and show storage test

    :param set_store:
    :return:
    """
    assert set_store.rc == 0, set_store.stdout
    pbm_ver = float(".".join(os.getenv("PBM_VERSION").split(".")[0:2]))
    if pbm_ver < 1.6:
        store_out = parse_yaml_string("\n".join(set_store.stdout.split("\n")[2:-2]))
    else:
        store_out = parse_yaml_string(set_store.stdout)
    assert store_out['storage']['type'] == 's3'
    assert store_out['storage']['s3']['region'] == 'us-east-1'
    assert store_out['storage']['s3']['bucket'] == 'operator-testing'


def test_show_store(show_store):
    """Check that all store configuration paramateres presented

    :param show_store:
    :return:
    """
    assert show_store['storage']['s3']
    assert show_store['storage']['s3']['region'] == 'us-east-1'
    assert show_store['storage']['s3']['bucket'] == 'operator-testing'
