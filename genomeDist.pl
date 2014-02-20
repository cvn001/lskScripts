#!/usr/bin/env perl
# Finds the distance between any two assemblies or raw reads
# Author: Lee Katz <lkatz@cdc.gov>

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use File::Basename;

my $start=time;

sub logmsg{ $|++; print STDERR ((time - $start)."\t"); print STDERR "@_\n"; $|--;}
exit(main());

sub main{
  my $settings={};
  GetOptions($settings,qw(help averages quiet method=s coverage=i kmerlength=i)) or die $!;
  die usage() if(!@ARGV || $$settings{help});
  my @asm=@ARGV;
  $$settings{method}||="mummer";
  $$settings{method}=lc($$settings{method});
  $$settings{coverage}||=2; $$settings{coverage}=1 if($$settings{coverage}<1);
  $$settings{kmerlength}||=18;


  if($$settings{method} eq 'mummer'){
    my $pdist=mummer(\@asm,$settings);
    
    print join("\t",".",@asm)."\n";
    for(my $i=0;$i<@asm;$i++){
      my $asm1=$asm[$i];
      print "$asm1\t";
      for(my $j=0;$j<@asm;$j++){
        my $asm2=$asm[$j];
        my $num=$$pdist{$asm1}{$asm2};
        $num=($$pdist{$asm1}{$asm2} + $$pdist{$asm2}{$asm1})/2 if($$settings{averages});
        print "$num\t";
      }
      print "\n";
    }
  }
  elsif($$settings{method} eq 'jaccard'){
    jaccardDistance(\@asm,$settings);
  }
  else {
    die "I do not know how to perform method $$settings{method}";
  }

  return 0;
}

sub jaccardDistance{
  my($genome,$settings)=@_;
  my %jDist;
  for(my $i=0;$i<@$genome-1;$i++){
    my %k1=kmerCount($$genome[$i],$settings);
    for(my $j=$i+1;$j<@$genome;$j++){
      my %k2=kmerCount($$genome[$j],$settings);
      my $jDist=jDist(\%k1,\%k2,$settings);
      print join("\t",@$genome[$i,$j],$jDist)."\n";
    }
  }
}

sub jDist{
  my($k1,$k2,$settings)=@_;
  my $minKCoverage=$$settings{coverage};

  logmsg "Finding intersection and union of kmers";
  my %kmerSet=kmerSets($k1,$k2,$settings);

  my $jDist=1-($kmerSet{intersection} / $kmerSet{union});

  logmsg "$jDist=1-($kmerSet{intersection} / $kmerSet{union})";
  return $jDist;
}

sub kmerSets{
  my($k1,$k2,$settings)=@_;
  
  my($intersectionCount,%union);

  # Find uniq kmers in the first set of kmers.
  # Also find the union.
  for my $kmer(keys(%$k1)){
    $intersectionCount++ if(!$$k2{$kmer});
    $union{$kmer}=1;
  }

  # Find uniq kmers in the second set of kmers.
  # Also find the union.
  for my $kmer(keys(%$k2)){
    $intersectionCount++ if(!$$k1{$kmer});
    $union{$kmer}=1;
  }

  my $unionCount=scalar(keys(%union));

  return (intersection=>$intersectionCount,union=>$unionCount);
}

sub kmerCount{
  my($genome,$settings)=@_;
  my $kmerLength=$$settings{kmerlength};
  my $minKCoverage=$$settings{coverage};
  logmsg "Counting $kmerLength-mers for $genome";
  my($name,$path,$suffix)=fileparse($genome,qw(.fastq.gz .fastq));
  if($suffix=~/\.fastq\.gz$/){
    open(FILE,"gunzip -c '$genome' |") or die "I could not open $genome with gzip: $!";
  } elsif($suffix=~/\.fastq$/){
    open(FILE,"<",$genome) or die "I could not open $genome: $!";
  } else {
    die "I do not understand the extension on $genome";
  }

  # count kmers
  my %kmer;
  my $i=0;
  while(<FILE>){
    my $mod=$i++ % 4;
    if($mod==1){
      chomp;
      my $read=$_;
      my $length=length($read)-$kmerLength+1;
      for(my $j=0;$j<$length;$j++){
        $kmer{substr($read,$j,$kmerLength)}++;
      }
    }
  }
  close FILE;

  # remove kmers with low depth
  while(my($kmer,$count)=each(%kmer)){
    delete($kmer{$kmer}) if($count<$minKCoverage);
  }

  logmsg "Found ".scalar(keys(%kmer))." unique kmers of depth > $minKCoverage";
  return %kmer;
}

sub mummer{
  my($asm,$settings)=@_;
  my %pdist=();
  for(my $i=0;$i<@$asm;$i++){
    my $asm1=$$asm[$i];
    for(my $j=0;$j<@$asm;$j++){
      my $asm2=$$asm[$j];
      my $prefix=join("_",$asm1,$asm2);
      if(!-e "$prefix.snps"){
        logmsg "Running on $prefix" unless($$settings{quiet});
        system("nucmer --prefix $prefix $asm1 $asm2 2>/dev/null"); die if $?;
        system("show-snps -Clr $prefix.delta > $prefix.snps 2>/dev/null"); die if $?;
      }
      my $numSnps=countSnps("$prefix.snps",$settings);
      $pdist{$asm1}{$asm2}=$numSnps;
      #$pdist{$asm2}{$asm1}=$numSnps;
    }
  }
  return \%pdist;
}

sub countSnps{
  my($snpsFile,$settings)=@_;
  my $num=0;
  open(SNP,$snpsFile) or die "Could not open $snpsFile: $!";
  while(<SNP>){
    $num++;
  }
  close SNP;
  $num-=5; # header
  die "internal parsing error" if ($num<0);
  return $num;
}

sub usage{
  "Finds the p-distance between two assemblies using mummer. With more genomes, it creates a table.
  Usage: $0 assembly.fasta assembly2.fasta [assembly3.fasta ...]
  -a to note averages. Switching the subject and query can reveal some artifacts in the algorithm.
  -q for minimal stdout
  -m method.  Can be mummer (default) or jaccard
    Mummer: uses mummer to discover SNPs and counts the total number
    Jaccard: (kmer method) counts 18-mers and calculates 1 - (intersection/union)
  -c minimum kmer coverage. Default: 2
  -k kmer length. Default: 18
  "
}