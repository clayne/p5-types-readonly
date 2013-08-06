use 5.008;
use strict;
use warnings;

package Types::ReadOnly;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.000_01';

use Type::Tiny 0.022 ();
use Types::Standard qw( Any Dict );
use Type::Utils;
use Type::Library -base, -declare => qw( ReadOnly Locked );

use Scalar::Util qw( reftype blessed );
use Hash::Util qw( hashref_locked unlock_hashref lock_ref_keys legal_ref_keys );

sub _dclone($) {
	require Storable;
	no warnings 'redefine';
	*_dclone = \&Storable::dclone;
	goto &Storable::dclone;
}

my %skip = map { $_ => 1 } qw/CODE GLOB/;
sub _make_readonly {
	my (undef, $dont_clone) = @_;
	if (my $reftype = reftype $_[0] and not blessed($_[0]) and not &Internals::SvREADONLY($_[0])) {
		$_[0] = _dclone($_[0]) if !$dont_clone && &Internals::SvREFCNT($_[0]) > 1 && !$skip{$reftype};
		&Internals::SvREADONLY($_[0], 1);
		if ($reftype eq 'SCALAR' || $reftype eq 'REF') {
			_make_readonly(${ $_[0] }, 1);
		}
		elsif ($reftype eq 'ARRAY') {
			_make_readonly($_) for @{ $_[0] };
		}
		elsif ($reftype eq 'HASH') {
			&Internals::hv_clear_placeholders($_[0]);
			_make_readonly($_) for values %{ $_[0] };
		}
	}
	Internals::SvREADONLY($_[0], 1);
	return;
}

our %READONLY_REF_TYPES = (HASH => 1, ARRAY => 1, SCALAR => 1, REF => 1);

declare ReadOnly,
	bless     => 'Type::Tiny::Wrapper',
	pre_check => sub
	{
		$READONLY_REF_TYPES{reftype($_)} and &Internals::SvREADONLY($_);
	},
	inlined_pre_check => sub
	{
		return (
			"\$Types::ReadOnly::READONLY_REF_TYPES{Scalar::Util::reftype($_)}",
			"&Internals::SvREADONLY($_)",
		);
	},
	post_coerce => sub
	{
		_make_readonly($_);
		return $_;
	},
	inlined_post_coerce => sub
	{
		"do { Types::ReadOnly::_make_readonly($_); $_ }";
	};

my $_FIND_KEYS = sub {
	my ($dict) = grep {
		$_->is_parameterized
			and $_->has_parent
			and $_->parent->strictly_equals(Dict)
	} $_[0], $_[0]->parents;
	return unless $dict;
	my @keys = sort keys %{ +{ @{ $dict->parameters } } };
	return unless @keys;
	\@keys;
};

declare Locked,
	bless     => 'Type::Tiny::Wrapper',
	pre_check => sub
	{
		return unless reftype($_) eq 'HASH';
		return unless hashref_locked($_);
		
		my $type    = shift;
		my $wrapped = $type->wrapped;
		
		if (my $KEYS = $wrapped->$_FIND_KEYS) {
			my $keys  = join "*#*", @$KEYS;
			my $legal = join "*#*", sort { $a cmp $b } legal_ref_keys($_);
			return if $keys ne $legal;
		}
		
		return !!1;
	},
	inlined_pre_check => sub
	{
		my @r;
		push @r, qq[Scalar::Util::reftype($_) eq 'HASH'];
		push @r, qq[Hash::Util::hashref_locked($_)];
		
		my $type    = $_[0];
		my $wrapped = $type->wrapped;
		
		if (my $KEYS = $wrapped->$_FIND_KEYS) {
			require B;
			push @r, B::perlstring(join "*#*", @$KEYS)
				.qq[ eq join "*#*", sort { \$a cmp \$b } Hash::Util::legal_ref_keys($_)];
		}
		
		return @r;
	},
	post_coerce => sub
	{
		my $type    = shift;
		my $wrapped = $type->wrapped;
		
		unlock_hashref($_);
		lock_ref_keys($_, @{ $wrapped->$_FIND_KEYS || [] });
		return $_;
	},
	inlined_post_coerce => sub
	{
		my $type    = shift;
		my $wrapped = $type->wrapped;
		
		my $qkeys;
		if (my $KEYS = $wrapped->$_FIND_KEYS) {
			require B;
			$qkeys = join q[,], '', map B::perlstring($_), @$KEYS;
		}
		
		return "Hash::Util::unlock_hashref($_); Hash::Util::lock_ref_keys($_ $qkeys); $_;";
	};

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Types::ReadOnly - type constraints and coercions for read-only data structures and locked hashes

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Types-ReadOnly>.

=head1 SEE ALSO

L<Type::Tiny::Manual>, L<Hash::Util>, L<Const::Fast>, L<MooseX::Types::Ro>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

