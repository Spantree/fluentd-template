Exec { path => ['/usr', '/usr/bin', '/usr/local/bin', '/usr/local/sbin', '/usr/sbin', '/sbin', '/bin'] }
if !$es_ipaddr {
	$es_ipaddr = "0.0.0.0"
}
if !$es_port {
	$es_port = "9200"
}
if !$logfile{
	$logfile = "/var/log/jboss/console.log"
}
###they use precise for every distro..
#Packages and Repos
class { 'apt':
	update_timeout       => undef
}
apt::source { 'treasuredata':
  location   => 'http://packages.treasure-data.com/precise/',
  release    => 'precise',
  repos      => 'contrib',
}
Package { 
	ensure => "installed",
	require => apt::source['treasuredata']
}
package { "td-agent": }
package { "libcurl3": }
package {"libcurl4-gnutls-dev": }
#Fluentd modules
exec { "/usr/lib/fluent/ruby/bin/fluent-gem install fluent-plugin-elasticsearch": 
	require => [Package['libcurl3'] , Package['libcurl4-gnutls-dev'] ]
}
exec { "/usr/lib/fluent/ruby/bin/fluent-gem install fluent-plugin-record-modifier": 
	require => [Package['libcurl3'] , Package['libcurl4-gnutls-dev'] ]
}

#Fluentd Configuration
augeas { "td-agent":
      incl    => "/etc/td-agent/td-agent.conf",
      lens    => "Httpd.lns",
      changes => [
	##### first source for nginx
	"set source[last()+1]/directive[1] 'type'",
	"set source[last()]/directive[1]/arg 'tail'",
	"set source[last()]/directive[2] 'format'",
	"set source[last()]/directive[2]/arg \"'format /^(?<time>.+) \[(?<level>[^\]]+)\] *(?<message>.*)$/'\"",
	"set source[last()]/directive[3] 'path'",
	"set source[last()]/directive[3]/arg /var/log/nginx/error.log",
	"set source[last()]/directive[4] 'tag'",
	"set source[last()]/directive[4]/arg 'nginx.hostapp'",
	##### match to add nginx tags
	"set match[last()+1]/arg 'nginx.hostapp'",
	"set match[last()]/directive[1] 'type'",
	"set match[last()]/directive[1]/arg 'record_modifier'",
	"set match[last()]/directive[2] 'gen_host'",
	"set match[last()]/directive[2]/arg '\${hostname}'",
	"set match[last()]/directive[3] 'gen_app'",
	"set match[last()]/directive[3]/arg 'nginx'",
	"set match[last()]/directive[4] 'tag'",
	"set match[last()]/directive[4]/arg 'es.send'",
	##### first source for catching errors and multiline exceptions
	"set source[last()+1]/directive[1] 'type'",
	"set source[last()]/directive[1]/arg 'tail'",
	"set source[last()]/directive[2] 'format'",
	"set source[last()]/directive[2]/arg 'multiline'",
	"set source[last()]/directive[3] 'format_firstline'",
	"set source[last()]/directive[3]/arg '/ERROR/'",
	"set source[last()]/directive[4] 'format1'",
	"set source[last()]/directive[4]/arg \"'/(?<stamp>[^ ]*) (?<level>[^ ]*) (?<class>[^ ]*) (?<host>[^ ]*)(?<message>.* [^ ]*)/'\"",
	"set source[last()]/directive[5] 'format2'",
	"set source[last()]/directive[5]/arg \"'/^(?<exception>.*)/'\"",
	"set source[last()]/directive[6] 'path'",
	"set source[last()]/directive[6]/arg '${logfile}'",
	"set source[last()]/directive[7] 'tag'",
	"set source[last()]/directive[7]/arg 'es.hostname'",
       ##### second source to catch INFO and WARNS
	"set source[last()+1]/directive[1] 'type'",
	"set source[last()]/directive[1]/arg 'tail'",
	"set source[last()]/directive[2] 'format'",
	"set source[last()]/directive[2]/arg \"'/^(?<time>[^ ]*) (?<level>[(INFO|WARN)]*) (?<class>[^ ]*) (?<host>[^ ]*)(?<message>.* [^ ]*)$/'\"",
	"set source[last()]/directive[3] 'path'",
	"set source[last()]/directive[3]/arg '${logfile}'",
	"set source[last()]/directive[4] 'tag'",
	"set source[last()]/directive[4]/arg 'es.hostname'",
       ##### es.hostname tag to append real hostname
	"set match[last()+1]/arg 'es.hostname'",
	"set match[last()]/directive[1] 'type'",
	"set match[last()]/directive[1]/arg 'record_modifier'",
	"set match[last()]/directive[2] 'gen_host'",
	"set match[last()]/directive[2]/arg '\${hostname}'",
	"set match[last()]/directive[3] 'gen_app'",
	"set match[last()]/directive[3]/arg 'jboss'",
	"set match[last()]/directive[4] 'tag'",
	"set match[last()]/directive[4]/arg 'es.send'",
       ##### finally the match that sends the data to elasticsearch	 
	"set match[last()+1]/arg 'es.send'",
	"set match[last()]/directive[1] 'type'",
	"set match[last()]/directive[1]/arg 'elasticsearch'",
	"set match[last()]/directive[2] 'logstash_format'",
	"set match[last()]/directive[2]/arg 'true'",
	"set match[last()]/directive[3] 'flush_interval'",
	"set match[last()]/directive[3]/arg '5s'",
	"set match[last()]/directive[4] 'host'",
	"set match[last()]/directive[4]/arg '${es_ipaddr}'",
	"set match[last()]/directive[5] 'port'",
	"set match[last()]/directive[5]/arg '${es_port}'",
      ],
      onlyif => "get match[last()]/arg != 'es.send'",
      require => [Package['libcurl3'] , Package['libcurl4-gnutls-dev'] ,Package['td-agent'] , Exec['/usr/lib/fluent/ruby/bin/fluent-gem install fluent-plugin-record-modifier'] , Exec['/usr/lib/fluent/ruby/bin/fluent-gem install fluent-plugin-elasticsearch'] ]
}
#Remove single quotes from conf
exec { "cleanquotes":
	command=> "sed -e \"s/'//g\" -i /etc/td-agent/td-agent.conf",
        require => Augeas['td-agent']
}
