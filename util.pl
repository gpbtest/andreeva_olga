#!/usr/bin/perl

use strict;
#use warnings;

use DBI;

sub dbInfo {
	return {
		name => 'test',
		host => '192.168.1.29',
		user => 'test_user',
		passwd => 't3stpa55'
	};
}

sub dbConnect {
	my $dbInfo = dbInfo();
	my $dsn = "DBI:mysql:database=" . $dbInfo->{name};
	$dsn .= ";host=" . $dbInfo->{host} if ($dbInfo->{host});
	$dsn .= ";port=" . $dbInfo->{host} if ($dbInfo->{port});
	my $dbh;
	eval {
		if ($dbh = DBI->connect($dsn, $dbInfo->{user} || '', $dbInfo->{passwd} || '',
			{RaiseError=>0, PrintError=>1, ShowErrorStatement=>1, AutoCommit=>1, mysql_enable_utf8=>1})) {
		} else {
			print STDERR "Connection failed: DSN = [$dsn], user = [$dbInfo->{user}] - $DBI::errstr\n";
		}
	};
	return $dbh || "Connection failed";
}

sub trim($) {
	my $str = shift;
	$str =~ s/^\s+|\s+$//g;
	return $str;
}

sub removeBOM($) {
	my $text = shift;
	$text =~ s/^(\x{feff}|\x{fffe}|\x{efbbbf}|\x{0000feff}|\x{fffe0000})//;
	return $text;
}
