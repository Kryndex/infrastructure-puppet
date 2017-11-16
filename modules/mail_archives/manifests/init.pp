#/etc/puppet/modules/mail_archives/manifests.init.pp

class mail_archives (

  $username   = 'modmbox',
  $groupname  = 'modmbox',
  $shell      = '/bin/bash',

  # override below in yaml
  $parent_dir,

  $required_packages = ['apache2-dev' , 'autotools-dev' , 'autoconf' , 'libapr1' , 'libapr1-dev' , 'libaprutil1' , 'libaprutil1-dev' , 'scons'],
){

# install required packages:
  package {
    $required_packages:
      ensure => 'present',
  }

  $install_dir  = "${parent_dir}/mail-archives"
  $mbox_source  = "${parent_dir}/mod_mbox"
  $mbox_svn_url = 'https://svn.apache.org/repos/asf/httpd/mod_mbox/trunk'
  $mbox_content = 'LoadModule mbox_module /usr/lib/apache2/modules/mod_mbox.so'
  $archives_www = "${parent_dir}/mail-archives.apache.org"
  $assets       = "${archives_www}/archives"

  group {
    $groupname:
      ensure => present,
      system => true,
  }->

  user {
    $username:
      ensure     => present,
      home       => "/home/${username}",
      system     => true,
      managehome => true,
      name       => $username,
      shell      => $shell,
      gid        => $groupname,
      require    => Group[$groupname],
  }

  file {
    $parent_dir:
      ensure => directory,
      owner  => 'root',
      group  => 'root',
      mode   => '0755';
    $install_dir:
      ensure => directory,
      owner  => $username,
      group  => 'root';
    "${install_dir}/raw":
      ensure => directory,
      mode   => '0755',
      owner  => $username,
      group  => 'root';
    "/home/${username}/scripts/":
      ensure  => 'directory',
      recurse => true,
      owner   => $username,
      group   => $username,
      mode    => '0755',
      source  => 'puppet:///modules/mail_archives/scripts';
    $archives_www:
      ensure => 'directory',
      mode   => '0755';
    $archives_www/mod_mbox:
      ensure => 'directory',
      owner   => $username,
      group   => root,
      mode   => '0755';
    $assets:
      ensure  => 'directory',
      recurse => true,
      mode    => '0755',
      source  => 'puppet:///modules/mail_archives/assets';

# symlink for apxs as SConstruct points to wrong dir

    '/usr/local/bin/apxs':
    ensure => link,
    target => '/usr/bin/apxs';

# loadmodule content to call mod_mbox module

    '/etc/apache2/mods-available/mod_mbox.load':
      ensure  => present,
      owner   => root,
      group   => root,
      mode    => '0644',
      content => $mbox_content,
      require => Package['apache2'];

  }

# execs

# download the svn source of mod_mbox

  exec {
    'download mbox svn':
      command => "/usr/bin/svn export ${mbox_svn_url} ${mbox_source}",
      cwd     => "${parent_dir}",
      creates => "${mbox_source}/NOTICE",
      timeout => 1200,
      require => File[$parent_dir];
  }

# build the requires mbox modules for apache2
  exec {
    'build mbox module':
      command => '/usr/bin/scons',
      cwd     => "${mbox_source}",
      creates => "${mbox_source}/mod_mbox.so",
      timeout => 1200,
      require => Package['scons'];
  }

# copy the compiled apache module to the expected apache modules directory
  exec {
    'copy mod_mbox.so':
      command => "/bin/cp ${mbox_source}/mod_mbox.so /usr/lib/apache2/modules/",
      cwd     => $mbox_source,
      user    => 'root',
      creates => '/usr/lib/apache2/modules/mod_mbox.so',
      timeout => 1200,
      require => Package['apache2'];
  }

# cron jobs

  cron {
    'public-mbox-rsync-raw':
      user        => $username,
      minute      => '42',
      command     => "/home/${username}/scripts/mbox-raw-rsync.sh",
      environment => "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin\nSHELL=/bin/sh", # lint:ignore:double_quoted_strings
      require     => User[$username];

    'create-archive-list':
      user        => $username,
      minute      => '14',
      hour        => '12',
      command     => "/home/${username}/scripts/create-archive-list /home/${username}/archives/raw > /home/${username}/archives/mbox-archives.list",
      environment => "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin\nSHELL=/bin/sh", # lint:ignore:double_quoted_strings
      require     => User[$username];

    'site-index':
      user        => $username,
      minute      => '51',
      hour        => '12',
      command     => "/home/${username}/scripts/site-index.py > ${$archives_www}/mod_mbox/index.html",
      environment => "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin\nSHELL=/bin/sh", # lint:ignore:double_quoted_strings
      require     => User[$username];
  }

}
