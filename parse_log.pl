#!/usr/bin/perl

use strict;
use warnings;

use DBI qw(:sql_types);
use POSIX qw(floor);
use Time::HiRes qw(time); # for time test

do './util.pl';

my @data;
if (open(F, '<', './out')) {
	binmode F, ':utf8';
	@data = <F>;
	close F;
	$data[0] = removeBOM($data[0]);
} else {
	die("Error reading file: " . $!);
}

my $re_created = '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}'; # e.g. 2012-02-13 14:39:22
my $re_int_id = '[\w\d\-]{16}'; # внутренний id сообщения, e.g. 1RwtJa-000AFB-07
my $re_address = '[^ <>@]+?@[^ <>@]+?'; # упрощённый вариант для нужд распознавания в логе, а не проверки корректности

my (@insert2message, @insert2log);

my ($t1, $t2) = (time(), 0);
my $count_out = 0;

foreach my $line (@data) {
	if ($line =~ /^($re_created) (($re_int_id) \<= (.*))$/) {
		my ($created, $str, $int_id, $tail) = ($1, $2, $3, $4);
		my $id = '';
		if ($tail =~ /^$re_address (.*)$/ && $1 =~ / id\=([\w\d\-.@]+)/) {
			$id = $1;
		}
		if ($id) {
			push @insert2message, {created => $created, str => $str, int_id => $int_id, id => $id};
		} else {
			# Если отправитель <> и U=mailnull, то id=xxxx отсутствует.
			# Чтобы не пропало, запишем это в общий log, а не в message.
			push @insert2log, {created => $created, str => $str, int_id => $int_id};
		}
	} elsif ($line =~ /^($re_created) (($re_int_id)(?: (=>|->|\*\*|==))? (.*))$/) {
		# В логе могут быть строки без внутреннего id сообщения ('int_id'); строки без них в базу не пишем.
		# Также "чёрная дыра" в строке => :blackhole: <tpxmuwr@somehost.ru> R=blackhole_router как бы намекает, что,
		# возможно, этот адрес записывать в поле 'address' не нужно. Саму строчку пишем в лог в любом случае.
		my ($created, $str, $int_id, $flag, $tail) = ($1, $2, $3, $4, $5);
		my $address;
		#if ($flag && $tail =~ /^($re_address)[ :]/ { # для флага '**' бывает ':' сразу после адреса; вариант без blackhole
		if ($flag && $tail =~ /^(?:($re_address)[ :]|.*? \<($re_address)\> )/) { # для флага '**' бывает ':' сразу после адреса; вариант с blackhole
			$address = $1 || $2; # Для варианта с blackhole в $2 будет tpxmuwr@somehost.ru
		}
		push @insert2log, {created => $created, str => $str, int_id => $int_id, address => $address};
	} else {
		$count_out++;
	}
}

printf("message: %d, log: %d, other: %d, total: %d\n", 0 + @insert2message, 0 + @insert2log, $count_out, 0 + @insert2message + @insert2log + $count_out);
$t2 = time() - $t1;
print $t2 . "\n";

eval {
	my $dbh = dbConnect();
	unless (ref($dbh)) {
		die($dbh); # die/exit from eval
	}
	my ($stmt, $sth);

	# also for time test
	$dbh->do(q/DELETE FROM message/);
	$dbh->do(q/DELETE FROM log/);

	my $valuesBlockNum = 9000; # >= 1

	# Для оптимизации заполнения базы используется вариант INSERT'а с одновременной вставкой нескольких строк:
	#   INSERT INTO tbl_name (a,b,c,d) VALUES (?,?,?,?), (?,?,?,?), (?,?,?,?);  -- здесь $valuesBlockNum = 3.
	# Количество запросов с INSERT - это количество строк для вставки, поделённое на $valuesBlockNum (поле 'repeat' в @groups ниже),
	# и если был остаток при делении, то плюс 1. Эти 2 группы запросов описаны в @groups.

	my @tables = (
		{table => 'message', data => \@insert2message, param => [qw(created id int_id str)]},
		{table => 'log', data => \@insert2log, param => [qw(created int_id str address)]}
	);
	foreach my $table (@tables) {
		my @groups = (
			{len => $valuesBlockNum, repeat => POSIX::floor(@{$table->{data}} / $valuesBlockNum)},
			{len => @{$table->{data}} % $valuesBlockNum, repeat => 1}
		);
		my $cursor = 0;
		foreach my $group (@groups) {
			next unless ($group->{repeat} > 0 && $group->{len} > 0);
			$stmt = '(' . join(',', ('?') x @{$table->{param}}) . ')';
			$stmt = sprintf("INSERT INTO %s (%s) VALUES", $table->{table}, join(',', @{$table->{param}})) . join(',', ($stmt) x $group->{len});
			$sth = $dbh->prepare($stmt);
			for (my $i = 0; $i < $group->{repeat}; $i++) {
				my $m = $cursor + $group->{len} - 1;
				my @lines = @{$table->{data}}[$cursor..$m];
				$cursor += $group->{len};
				my $p = 1;
				foreach my $href (@lines) {
					foreach my $par (@{$table->{param}}) {
						$sth->bind_param($p++, $href->{$par}, SQL_VARCHAR);
					}
				}
				$sth->execute() or die $sth->errstr;
			}
		}
	}
};
if ($@) {
	print STDERR $@ . "\n";
}

$t2 = time() - $t1;
print $t2 . "\n";
