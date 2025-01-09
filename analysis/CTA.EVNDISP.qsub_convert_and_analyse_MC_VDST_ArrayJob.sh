#!/bin/bash
#
# script to convert sim_tel output files to EVNDISP DST file and then run eventdisplay
#
#

# set the right observatory (environmental variables)
source $EVNDISPSYS/setObservatory.sh CTA

ILIST=SIMTELLIST
PART=PAAART
SUBA="ARRAY"
KEEP=KEEEEEEP
ACUT=ARC
DSET=DATASET
PEDFILE=PPPP
STEPSIZE=STST
ILINE=${1}
if [[ -v ${SGE_TASK_ID} ]] && [[ ! -z ${SGE_TASK_ID} ]]; then
    ILINE=$SGE_TASK_ID
else
    # HTCondor ProcIDs start at 0
    let "ILINE = $ILINE + 1"
fi

# set array
FIELD=$SUBA

# TMPDIR - usually set on cluster nodes; useful for testing
if [[ ! -n "$TMPDIR" ]]; then
    TMPDIR="$CTA_USER_DATA_DIR/tmp/${DSET}"
    mkdir -p "${TMPDIR}"
fi

###################################
# converter command line parameter
COPT="-pe"
# prod3(b): read effective focal lengths from external file
if [[ $DSET == *"prod3"* ]]
then
    COPT="-rfile ${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod3b.EffectiveFocalLength.dat"
    COPT="$COPT -pe"
fi
# (prod4 and later effective focal lengths included in simulation file)
COPT="$COPT -c $PEDFILE"

# eventdisplay command line parameter
# OPT="-averagetzerofiducialradius=0.5 -reconstructionparameter $ACUT"
OPT="-imagesquared -averagetzerofiducialradius=0.5 -reconstructionparameter $ACUT"
OPT="$OPT -writeimagepixellist"
if [[ $DSET == *"prod3"* ]]
then
    # needs to be the same as used for IPR graph preparation
    OPT="$OPT -ignoredstgains"
fi

# set simtelarray file and cp simtelarray.gz file to TMPDIR
if [ ! -e $ILIST ]
then
   echo "ERROR: list of simulation files does not exist: $ILIST"
   exit
fi

# get file list (of $STEPSIZE files)
let "ILINE = $ILINE * $STEPSIZE"
echo "getting line(s) $ILINE from list"
echo "list: $ILIST"
IFIL=`head -n $ILINE $ILIST | tail -n $STEPSIZE`
IFIL0=`head -n $ILINE $ILIST | tail -n 1`
echo "DATA FILE(S)"
echo $IFIL
################################
# copy files on temporary disk
echo
echo "COPYING FILES TO $TMPDIR"
# check if files are on local disc (lustre) or on dCache
for F in $IFIL
do
    if [ ! -e $F ]
    then
       echo "ERROR: SIMTELFILE does not exist:"
       echo $F
       exit
    fi
    if [[ $F = *acs* ]]
    then
         export DCACHE_CLIENT_ACTIVE=1
         echo "F $F"
         G=`basename $F`
         echo "G $G"
         #dccp $F $TMPDIR"/"$G
         cp -v -f /pnfs/ifh.de/$F $TMPDIR"/"$G
    else
         cp -v -f $F $TMPDIR"/"
    fi
done

#####################################
# output file

EXTE="${IFIL0##*.}"
OFIL=`basename $IFIL0 .${EXTE}`
echo
echo "OUTPUT FILE $OFIL ${EXTE}"

####################################################################
# loop over all arrays
for N in $FIELD
do
# remove spaces
   N=`echo $N | tr -d ' '`
   echo "RUNNING _${N}_"
# output data files are written to this directory
   ODIR=${CTA_USER_DATA_DIR}/analysis/AnalysisData/${DSET}/${N}/EVNDISP/${PART}/
   mkdir -p $ODIR

####################################################################
# execute zero suppression
#
# input sim_telarray file: $SIMFIL
# ($SIMFIL should be set then to the zero suppressed file)
#
# best to write to output (zero suppressed file) to the temporary disk on the
# current note: $TMPDIR/<zerosuppressed file>
#
# $HESSIOSYS/bin/ ....

####################################################################
# execute converter
   SIMFIL=`ls $TMPDIR/*.simtel.${EXTE}`
   echo "TMPDIR FILES " $SIMFIL
   if [[ $DSET == *"prod3"* ]]
   then
       if [[ $DSET == *"paranal"* ]] && [[ $DSET != *"prod3b"* ]]
       then
           DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod3${N}.lis
       elif [[ $DSET == *"NSB"* ]]
       then
           DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod3${N}.lis
       elif [[ $DSET == *"LaPalma"* ]]
       then
           DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod3${N}.lis
       else
           DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod3Sb${N:1}.lis
       fi
   elif [[ $DSET == *"prod4"* ]]
   then
       DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod4${N}.lis
   elif [[ $DSET == *"prod5"* ]]
   then
       DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod5${N}.lis
   elif [[ $DSET == *"prod6"* ]]
   then
       DETGEO=${CTA_EVNDISP_AUX_DIR}/DetectorGeometry/CTA.prod6${N}.lis
   fi
   ls -lh $DETGEO
   ls -lh $SIMFIL
   ls -lh $TMPDIR
   $EVNDISPSYS/bin/CTA.convert_hessio_to_VDST $COPT \
                                              -a $DETGEO \
                                              -o $TMPDIR/$OFIL.root \
                                              $SIMFIL &> $TMPDIR/$OFIL.$N.convert.log

####################################################################
# execute eventdisplay
  if [ -e $TMPDIR/$OFIL.root ]
  then
      $EVNDISPSYS/bin/evndisp -sourcefile $TMPDIR/$OFIL.root $OPT \
                              -outputdirectory $TMPDIR \
                              -calibrationdirectory $TMPDIR &> $TMPDIR/$OFIL.$N.evndisp.log
  else
      echo "DST file not found: $TMPDIR/$OFIL.root" >& $TMPDIR/$OFIL.$N.evndisp.log
  fi


####################################################################
# get runnumber and azimuth and rename output files; mv them to final destination
  if [ -e $TMPDIR/$OFIL.root ]
  then
      MCAZ=`$EVNDISPSYS/bin/printRunParameter $TMPDIR/$OFIL.root -mcaz`
      RUNN=`$EVNDISPSYS/bin/printRunParameter $TMPDIR/$OFIL.root -runnumber`

    # mv log files into evndisp root file
      if [ -e $TMPDIR/$OFIL.$N.evndisp.log ]
      then
          $EVNDISPSYS/bin/logFile evndispLog $TMPDIR/${RUNN}.root $TMPDIR/$OFIL.$N.evndisp.log
      fi
      if [ -e $TMPDIR/$OFIL.$N.convert.log ]
      then
          $EVNDISPSYS/bin/logFile convLog $TMPDIR/${RUNN}.root $TMPDIR/$OFIL.$N.convert.log
      fi
      cp -v -f $TMPDIR/[0-9]*.root ${ODIR}/${RUNN}CTAO_${ILINE}_${MCAZ}deg.root
  else
      echo "No root files found!"
      if [ -e $TMPDIR/$OFIL.$N.convert.log ]; then
         cp -f -v $TMPDIR/$OFIL.$N.convert.log $ODIR/
      fi
      if [ -e $TMPDIR/$OFIL.$N.evndisp.log ]; then
         cp -f -v $TMPDIR/$OFIL.$N.evndisp.log $ODIR/
      fi
  fi

####################################################################
# move dst (if required) and evndisp files to data directory
   if [ "$KEEP" == "1" ]
   then
      mkdir -p $ODIR/VDST
      cp -v -f $TMPDIR/$OFIL.root $ODIR/VDST/
   fi
   ls -lh $TMPDIR/*.root
# clean up
   rm -f $TMPDIR/$OFIL.root
   rm -f $TMPDIR/[0-9]*.root
   echo "==================================================================="
   echo
done

exit
