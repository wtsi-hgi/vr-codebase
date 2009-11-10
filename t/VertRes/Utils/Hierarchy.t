#!/usr/bin/perl -w
use strict;
use warnings;

BEGIN {
    use Test::Most tests => 24;
    
    use_ok('VertRes::Utils::Hierarchy');
    use_ok('VertRes::IO');
    use_ok('File::Copy');
}

my $h_util = VertRes::Utils::Hierarchy->new();
isa_ok $h_util, 'VertRes::Base';

# setup our files and paths
my $io = VertRes::IO->new();
my $si_file = $io->catfile('t', 'data', 'sequence.index');
ok -s $si_file, 'sequence.index file ready to test with';
my $bam_file = $io->catfile('t', 'data', 'headed1.bam');
ok -s $bam_file, 'bam file ready to test with';
my $temp_dir = $io->tempdir();
ok my $vrtrack = VRTrack::VRTrack->new({database => 'g1k_meta', host => 'mcs4a', port => 3306, user => 'vreseq_ro'}), 'setup vrtrack accessing g1k_meta';

my $lane_path = '/path/to/META/SRP000031/NA06986/SLX/Solexa-5459/SRR003670';
is_deeply {$h_util->parse_lane($lane_path)}, {study => 'SRP000031',
                                              sample => 'NA06986',
                                              platform => 'SLX',
                                              library => 'Solexa-5459',
                                              lane => 'SRR003670'}, 'parse_lane test';

ok $h_util->check_lanes_vs_sequence_index([$lane_path], $si_file), 'check_lanes_vs_sequence_index test';
$lane_path = '/path/to/META/SRP000031/NA06986/SLX/Solexa_5459/SRR003670';
ok $h_util->check_lanes_vs_database([$lane_path], $vrtrack), 'check_lanes_vs_database test';
#ok ! $h_util->check_lanes_vs_database([$lane_path], $vrtrack, 1), 'check_lanes_vs_database check all test'; # too slow...

# setup for and test create_release_hierarchy()
# *** probably need to drop the test database and recreate it each time...
# mysql -hmcs4a -uvreseq_rw -pt3aml3ss
# > create database vrtrack_vertres_test;
# > exit
# mysql -hmcs4a -uvreseq_rw -pt3aml3ss vrtrack_vertres_test < ~/src/vert_reseq/Docs/schema/VRtrack.schema
# update_vrmeta.pl --database vrtrack_vertres_test --samples t/data/vrtrack_vertres_test.samples --index t/data/vrtrack_vertres_test.si
# perl -MVRTrack::VRTrack -MVRTrack::Lane -Mstrict -we 'my $vrtrack = VRTrack::VRTrack->new({host => "mcs4a", port => 3306, user => "vreseq_rw", password => "t3aml3ss", database => "vrtrack_vertres_test"}); my $all_lanes = $vrtrack->processed_lane_hnames(); my $count = 0; foreach my $lane_hname (sort @{$all_lanes}) { my $lane = VRTrack::Lane->new_by_hierarchy_name($vrtrack, $lane_hname); $lane->is_processed("import", 1); $lane->is_processed("mapped", 1); foreach my $file (@{$lane->files()}) { $file->is_processed("import", 1); $file->update; } my $mapping = $lane->add_mapping(); my $assembly = $mapping->assembly("NCBI37"); if ( ! $assembly) { $assembly = $mapping->add_assembly("NCBI37"); } my $exe; $count++; if ($count <= 2) { $exe = "bwa"; } else { $exe = "ssaha"; } my $mapper = $mapping->mapper($exe, "1.5"); if ( ! $mapper) { $mapper = $mapping->add_mapper($exe, "1.5"); } $mapping->update; $lane->update; }'
ok $vrtrack = VRTrack::VRTrack->new({database => 'vrtrack_vertres_test', host => 'mcs4a', port => 3306, user => 'vreseq_ro'}), 'setup vrtrack accessing vrtrack_vertres_test';
my $release_dir = $io->catfile($temp_dir, 'REL');
my $mapping_tar_gz = $io->catfile($temp_dir, 'mapping.tar.gz');
copy($io->catfile('t', 'data', 'mapping_hierarchy_with_bams.tar.gz'), $mapping_tar_gz);
ok -s $mapping_tar_gz, 'mapping_hierarchy_with_bams.tar.gz copied and ready to test with';
system("tar -xz -C $temp_dir -f $mapping_tar_gz");
ok -d $io->catfile($temp_dir, 'mapping'), 'mapping hierarchy extracted and ready to test with';
my @mapping_paths;
my @expected_rel_paths;
foreach my $lane_path ('mapping/proj1/ind1/SLX/lib1/lane1', # 1.pe.raw.sorted.bam
                       'mapping/proj1/ind1/SLX/lib1/lane2', # 4.se.raw.sorted.bam
                       'mapping/proj2/ind2/454/lib3/lane3/', # 7.se.raw.sorted.bam
                       'mapping/proj2/ind2/454/lib3/lane4/') { # 10.pe.raw.sorted.bam
    push(@mapping_paths, $io->catfile($temp_dir, $lane_path));
    my $rel_path = $lane_path;
    $rel_path =~ s/^mapping\///;
    push(@expected_rel_paths, $io->catfile($temp_dir, 'REL', $rel_path));
}
my @expected_rel_bams = ('pe.raw.sorted.bam', 'se.raw.sorted.bam', 'se.raw.sorted.bam', 'pe.raw.sorted.bam');
my @expected_rel_bam_paths;
foreach my $rel_path (@expected_rel_paths) {
    my $expected_bam = shift @expected_rel_bams;
    push(@expected_rel_bam_paths, $io->catfile($rel_path, $expected_bam));
}

is_deeply [$h_util->create_release_hierarchy(\@mapping_paths, $release_dir,
                                             vrtrack => $vrtrack,
                                             slx_mapper => 'bwa',
                                             '454_mapper' => 'ssaha',
                                             assembly_name => 'NCBI37')], \@expected_rel_bam_paths, 'create_release_hierarchy test';

my $created_links = 0;
foreach my $link (@expected_rel_bam_paths) {
    $created_links++ if -e $link;
}
is $created_links, 4, 'create_release_hierarchy created the correct bam symlinks';

# lane_info test
my $mouse_reseq_track_db = { host => 'mcs4a', port => 3306, user => 'vreseq_ro', database => 'mouse_reseq_track' };
ok my %info = $h_util->lane_info('3034_8', db => $mouse_reseq_track_db, qc_passed => 1, mapped => 1), 'lane_info ran ok';
is $info{sample}, '129P2_1', 'lane_info gave correct sample';
is $info{individual_coverage}, 22.39, 'lane_info had the correct individual_coverage';
# needs more thougher tests for all the different ways of calling lane_info...

# hierarchy_coverage test
my $cov = $h_util->hierarchy_coverage(individual => ['129P2/OlaHsd'], db => $mouse_reseq_track_db, qc_passed => 1, mapped => 1);
cmp_ok $cov, '>=', 22.39, 'hierarchy_coverage direct test';
my $cov2 = $h_util->hierarchy_coverage(lane => '3034_8', level => 'individual', db => $mouse_reseq_track_db, qc_passed => 1, mapped => 1);
cmp_ok $cov, '>=', 22.39, 'hierarchy_coverage lane level test';
is $cov, $cov2, 'coverage was the same in both tests';

# dcc_filename test
is $h_util->dcc_filename($bam_file), 'NA11918.SLX.bwa.SRP000031.2009_08', 'dcc_filename test';

# fix_simple_swaps test?? netapp_lane_path not yet implemented
TODO {
    local $TODO = "fix_simple_swaps test not yet done, netapp_lane_path not yet implemented...\n";
    ok 0;
    ok 0;
}

exit;
