package Data::Reuse;

# set up version info
BEGIN {
    $VERSION = '0.04';
}    #BEGIN

# be as strict and verbose as possible
use strict;
use warnings;

# we need this otherwise nothing works
use Data::Alias qw(alias copy);

# needed for creation of unique keys
use Digest::MD5 qw(md5);

=for Explanation:
     Since Data::Alias uses Exporter, we might as well do that also.  Otherwise
     we'd probably hack an import method ourselves

=cut

use base 'Exporter';
our @EXPORT      = qw(reuse);
our @EXPORT_OK   = qw(reuse alias copy);
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# ID prefixes
my $U = "\1U\1";
my $S = "\1S\1";
my $A = "\1A\1";
my $H = "\1H\1";

# set up data store with predefined ro undef value
my %reuse = ( $U => undef ); # must NOT use alias

# mark constants as read only
Internals::SvREADONLY $_, 1 foreach ( $U, $S, $A, $H, $reuse{$U} );

# recursion level
my $level = 0;

# references being handled
my %handling;

# satisfy -require-
1;

#---------------------------------------------------------------------------
# reuse
#
#  IN: 1..N values to be folded into constants
# OUT: 1..N same as input, but read-only and folded

sub reuse (@); # needed because of recursion
sub reuse (@) {

    # we're one level deeper
    $level++;

    # there are values specified that haven't been folded yet or are undef
    if ( alias my @special = grep { !defined or !exists $reuse{$_} } @_ ) {

        # values specified that haven't been folded yet
        if ( alias my @new = grep { defined() } @special ) {
            foreach (@new) { # natural aliasing

                # reference being handled, make sure it is known
                if ( exists $handling{$_} ) {
                     alias $reuse{$_} ||= $_;
                }

                # handle references
                elsif ( my $ref = ref() ) {
                    $handling{$_} = $level;
                    my $id;

                    # aliasing everything in here
                    alias {

                        # all elements of list
                        if ( $ref eq 'ARRAY' ) {
                            $id = _list_id( $_ );

                            # not seen, recurse
                            if ( !exists $reuse{$id} ) {
                                my @list = @{$_};
                                (@list) = reuse @list;
                                copy Internals::SvREADONLY @list, 1;

                                # recursive structures may be replaced
                                $id = _list_id( $_ );
                            }
                        }

                        # all values of hash
                        elsif ( $ref eq 'HASH' ) {
                            $id = _hash_id( $_ );

                            # not seen, recurse, set result if first
                            if ( !$reuse{$id} ) {
                                my %hash = %{$_};
                                ( @hash{ keys %hash } ) = reuse values %hash;
                                copy Internals::SvREADONLY %hash, 1;

                                # recursive structures may be replaced
                                $id = _hash_id( $_ );
                            }
                        }

                        # the value of a scalar ref
                        elsif ( $ref eq 'SCALAR' ) {
                            my $scalar = ${$_};

                            # may be reused
                            if ( defined $scalar ) {
                                $id = md5( $S . $scalar );

                                # not seen, recurse, set result if first
                                if ( !$reuse{$id} ) {
                                    ($scalar) = reuse $scalar;
                                    copy Internals::SvREADONLY $scalar, 1;

                                    # recursive structures may be replaced
                                    $id = md5( $S . $scalar );
                                }
                            }

                            # always reuse the default undef value
                            else {
                                $id = $U;
                            }
                        }

                        # huh?
                        else {
                            die "Cannot handle references of type '$ref'";
                        }

=for Explanation:
     When called in void context, perl may actually have used a memory location
     for a temporary data structure that may return later with a different
     content.  As we don't want to equate those two different structures, we
     are not going to save this reference if called in void context.  And we
     are also not going to overwrite anything that's there already.

=cut

                        $reuse{$id} ||= $_ if defined wantarray;

                        # store in data store
                        $reuse{$_} = $reuse{$id} || $_;
                    };   #alias

                    # done handling this ref
                    delete $handling{$_};
                }

                # not a ref
                else {

                    # not readonly already, make a read only copy
                    $_ = $_, Internals::SvREADONLY $_, 1
                      if !Internals::SvREADONLY $_;

                    # store in data store
                    alias $reuse{$_} = $_;
                }
            }
        }
    }

    # done on this level
    $level--;

    # return aliases of the specified values if needed
    alias return @reuse{ map { defined() ? $_ : $U } @_ }
      if defined wantarray;
}    #reuse

#---------------------------------------------------------------------------
#
# Internal methods
#
#---------------------------------------------------------------------------
# _hash_id
#
# Return the ID for a hash ref
#
#  IN: 1 hash ref
# OUT: 1 id

sub _hash_id {
    alias my %hash = %{ $_[0] };

    return md5( $H . join $;,
      map { $_ => ( defined $hash{$_} ? $hash{$_} : $U ) } sort keys %hash );
}    #_hash_id

#---------------------------------------------------------------------------
# _list_id
#
# Return the ID for a list ref
#
#  IN: 1 list ref
# OUT: 1 id

sub _list_id {
    alias my @list = @{ $_[0] };

    return md5( $A . join $;, map { defined() ? $_ : $U } @list );
}    #_list_id

#---------------------------------------------------------------------------
#
# Debug methods
#
#---------------------------------------------------------------------------
# _reuse
#
# Return hash ref of hash containing the constant values
#
# OUT: 1 hash ref

sub _reuse { return \%reuse } #_reuse

#---------------------------------------------------------------------------

__END__

=head1 NAME

Data::Reuse - share constant values with Data::Alias

=head1 SYNOPSIS

 use Data::Reuse qw(reuse);
 reuse my $listref = [ 0, 1, 2, 3 ];
 reuse my $hashref = { zero => 0, one => 1, two => 2, three => 3 };
 print \$listref->[0] == \$hashref->{zero}
   ? "Share memory\n" : "Don't share memory\n";

 use Data::Reuse qw(reuse);
 my @list = ( 0, 1, 2, 3 );
 my %hash = ( zero => 0, one => 1, two => 2, three => 3 );
 reuse \@list, \%hash;
 print \$list[0] == \$hash{zero}
   ? "Share memory\n" : "Don't share memory\n";

 use Data::Reuse qw(reuse alias);  # use alias semantics from Data::Alias
 alias my @foo = reuse ( 0, 1, 2, 3 );
 alias my %bar = reuse ( zero => 0, one => 1, two => 2, three => 3 );

 print \$foo[0] == \$bar{zero}
   ? "Share memory\n" : "Don't share memory\n";

=head1 DESCRIPTION

By default, Perl doesn't share literal ( 0, 'foo' , "bar" ) values.  That's
because once a literal value is stored in variable (a container), the contents
of that container can be changed.  Even if such a container is marked
"read-only" (e.g. with a module such as L<Scalar::ReadOnly>), it will not
cause the values to be shared.  So each occurrence of the same literal value
has its own memory location, even if it is internally marked as read-only.

In an ideal world, perl would keep a single copy of each literal value
(container) and have all occurrences in memory point to the same container.
Once an attempt is made to change the container would perl make a copy of the
container and put the new value in there.  This principle is usually referred
to as Copy-On-Write (COW).  Unfortunately, perl doesn't have this.

Comes in the L<Data::Alias> module which allows you to share containers
between different variables (amongst other things).  But it still does not
allow you to have literal values share the same memory locations.

Comes in this module, the L<Data::Reuse> module, which allows you to easily
have literal and read-only values share the same memory address.  Which can
save you a lot of memory when you are working with large data structures with
similar values.  Which is especially nice in a mod_perl environment.

Of course, no memory savings will occur for literal values that only occur
once.  So it is important that you use the "reuse"

=head1 SUBROUTINES

=head2 reuse

 my $listref = reuse [ 1, 2, 3 ];
 my $hashref = reuse { one => 1, two => 2, three => 3 };

 my @list = ( 1, 2, 3 );
 my %hash = ( one => 1, two > 2, three => 3 );
 reuse \@list, \%hash;

The "reuse" function is the workhorse of this module.  Exported by default.
It will investigate the given data structures and reuse any literal values
as much as possible and return aliases to the given data structures.

=head2 alias

 use Data::Reuse qw(alias);
 alias my @list = reuse ( 1, 2, 3 );
 alias my %hash = reuse ( one => 1, two > 2, three => 3 );

The "alias" semantics from the L<Data::Alias> module, not exported by default.
Can be imported from L<Data::Reuse> for your convenience.  Please see the
L<Data::Alias> module's documentation for more information.

=head2 copy

 use Data::Reuse qw(copy);

The "copy" semantics from the L<Data::Alias> module, not exported by default.
Can be imported from L<Data::Reuse> for your convenience.  Please see the
L<Data::Alias> module's documentation for more information.

=head1 EXAMPLE

=head2 inventory information in a hotel

Inventory information ofter consists of many similar values.  In this
particular example of a hotel and whether its rooms have inventory for the
given period, the dates are always in the same range, the rate ID's are always
the same values from a set, the prices for a particular room / rate combination
will most likely be very similar, and the number of rooms available as well.

Once read from the database, they are most likely to remain constant for the
remainder of the lifetime of the process.  It therefore makes sense to fold
the constants into the same memory locations.

 use Data::Reuse qw(reuse);

 my $sth = $dbh->prepare( <<"SQL" );
 SELECT room_id, date, rate_id, price, rooms
   FROM inventory
  WHERE date BETWEEN '$first_date' AND '$last_date'
    AND hotel_id = $hotel_id
  ORDER BY date
 SQL
 my $sth->execute;

 my ( $room_id, $date, $rate_id, $price, $rooms );
 $sth->bind_columns( \( $room_id, $date, $rate_id, $price, $rooms ) );

 my %result;
 push @{ $result{$room_id} }, reuse [ $date, $rate_id, $price, $rooms ]
   while $sth->fetch;

Suppose a hotel has, in a period of 365 days, 10 different room types (ID's)
with an average of 2 different rate types, having a total of 10 different
prices and 10 different number of available rooms.

Without using this module, this would take up 365 x 10 x 2 x 2 = 14400 scalar
values x 24 bytes = 350400 bytes.  With using this module, this would use
365 + 10 + 2 + 10 + 10 = 387 scalar values x 24 bytes = 9288 bytes.  Quite a
significant difference!  Now multiply this by hundreds of hotels, and you see
that the space savings can become B<very> significant.

=head1 THEORY OF OPERATION

Each scalar value reused is internally matched against a hash with all
reused values.  This also goes for references, which are reused recursively.
For scalar values, the value itself is used as a key.  For references, an
MD5 hash is used as the key.

All values are then aliased to the values in the hash (using <Data::Alias>'s
C<alias> feature) and returns as aliases when needed.

=head1 CAVEATS

=head2 reuse lists and hashes

Unfortunately, it is not possible to directly share lists and hashes.  This
is because perl will make copies again after the reusing action:

 reuse my @list = ( 1, 2, 3 );

is functionally equivalent with:

 reuse ( 1, 2, 3 );
 my @list = ( 1, 2, 3 );

so, this will cause the values B<1>, B<2> and B<3> to be in the internal reused
values hash, but the assignment of C<@list> will use new copies, thus
annihiliting any memory savings.

Alternately:

 my @list = reuse( 1, 2, 3);

will not produce any space savings because the values are copied again by
perl after having been reused.  If you still want to use this type of idiom,
you can with the help of the "alias" function of the L<Data::Alias> module,
which you can also import from the L<Data::Reuse> module for your convenience:

 use Data::Reuse qw(alias reuse);
 alias my @list = reuse( 1, 2, 3);

will then generate the desired result.

=head1 FREQUENTLY ASKED QUESTIONS

None so far.

=head1 TODO

=head2 merging key and value

Currently, each reused value is kept at least twice in memory: once as a key,
and once as a value.  Deep down in the inside of perl, it is possible to create
a hash entry of which the key is in fact an external SV.  In an ideal world,
this feature should be used so that each reused value really, really only
occurs once in memory.  Suggestions / Patches to achieve this feature are
B<very> welcome!

If this proves to be impossible to do, then probably we need to use MD5 strings
for all values to reduce memory requirements.

=head1 ACKNOWLEDGEMENTS

The Amsterdam Perl Mongers for feedback on various aspects of this module.  And
of course Matthijs van Duin for making it all possible with the very nice
L<Data::Alias> module.

=head1 REQUIRED MODULES

 Data::Alias (1.0)

=head1 AUTHOR

Elizabeth Mattijsen <liz@dijkmat.nl>

Copyright (C) 2006 Elizabeth Mattijsen.  All rights reserved.
This program is free software; you can redistribute it and/or modify 
it under the same terms as Perl itself.

=cut
