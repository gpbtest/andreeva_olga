use strict;
use warnings;
use DBI qw(:sql_types);
use CGI qw(escapeHTML);

do File::Spec->rel2abs('../util.pl', $ENV{DOCUMENT_ROOT});

my $more;
my $result = '';

my $cgi = CGI->new();
my $address = trim($cgi->param('address') || '');
my $address_esc = CGI::escapeHTML($address);
my $exact = ($cgi->param('exact') ? 1 : 0);
my $search = 0; # флаг для управления фокусом в зависимости от факта поиска и наличия результата

if ($address) {
	eval {
		my $dbh = dbConnect();
		unless (ref($dbh)) {
			die($dbh); # die/exit from eval
		}
		my $condition;
		if ($exact) {
			$condition = q/ address = ? /;
		} else {
			$condition = q/ address LIKE CONCAT('%', ?, '%') /;
		}
		my $stmt = q/
			(SELECT SQL_CALC_FOUND_ROWS created, str, int_id FROM log WHERE int_id IN (SELECT int_id FROM log WHERE / . $condition . q/))
			UNION ALL
			(SELECT created, str, int_id FROM message WHERE int_id IN (SELECT int_id FROM log WHERE / . $condition .q/))
			ORDER BY int_id, created LIMIT 0, 100
		/;
		my $sth = $dbh->prepare($stmt);
		$sth->bind_param(1, $address, SQL_VARCHAR);
		$sth->bind_param(2, $address, SQL_VARCHAR);
		$sth->execute();
		my @result;
		while (my $href = $sth->fetchrow_hashref()) {
			$href->{str} = CGI::escapeHTML($href->{str});
			push @result, $href;
		}
		$sth = $dbh->prepare(q/SELECT FOUND_ROWS() AS 'found_rows'/);
		$sth->execute();
		my $href = $sth->fetchrow_hashref();
		if ($href) {
			$more = $href->{found_rows} - @result;
		}
		if (@result) {
			foreach my $href (@result) {
				$result .= qq{<li><b>$href->{created}</b><br>$href->{str}</li>\n};
			}
			$result = qq{<ol>$result</ol>} . ($more ? qq{<br><p style="text-align: center;">Ещё результатов: $more</p>} : '');
			$search = 1;
		} else {
			$result  = qq{<p style="text-align: center;">Ничего не найдено.</p>};
			$search = -1;
		}
	};
}

print "Content-Type: text/html\n\n";

print q{<html><body>
<div style="text-align: center; margin: 50px;"><form method="get" action="">
	<input type="text" name="address" placeholder="Адрес получателя" value="} . $address_esc . q{">
	<label><input type="checkbox" name="exact" value="1"} . (!$address || $exact ? q{ checked="checked"} : '') . q{> Точное совпадение</label>
	<br><br><input type="submit" value="Искать">
</form></div>
<script>
document.querySelector('form').addEventListener('submit', function(e) {
	var t = document.querySelector('input[name="address"]').value;
	document.querySelector('input[name="address"]').value = t.replace(/^\s+|\s+$/g, '');
	if (!document.querySelector('input[name="address"]').value) {
		e.preventDefault();
		document.querySelector('input[name="address"]').focus();
	}
}, false);
</script>} . ($search > 0 ? '' : q{
<script>
var t = document.querySelector('input[name="address"]').value;
document.querySelector('input[name="address"]').value = '';
document.querySelector('input[name="address"]').focus();
document.querySelector('input[name="address"]').value = t;
</script>
}) . $result . q{
</body></html>};
