#!/bin/bash
#
# script to convert sim_tel output files and then run eventdisplay analysis
#
#
#######################################################################

SUBC="condor"
h_cpu="11:29:00"
h_vmem="10G"
tmpdir_size="100G"

if [ ! -n "$1" ] && [ ! -n "$2" ] && [ ! -n "$3" ]
then
   echo
   echo "
    ./CTA.EVNDISP.sub_convert_and_analyse_MC_VDST_ArrayJob.sh
                  <sub array list> <list of sim_telarray files> <particle> <data set>
                  [keep simtel.root files (default off=0)] [log file directory counter] [qsub options]

   CTA ANALYSIS

     <sub array list>          text file with list of subarray IDs

     <particle>                gamma_onSource , gamma_cone, proton , electron (helium, ...)

     <data set>                e.g. prod5-LaPalma-20deg-sq2-LL, ...

   NOTE: HARDWIRED FILE NAMES IN QSUB SCRIPTS !!

     [keep DST.root files]  keep and copy converted simtel files (DST files) to output directory (default off=0)

    output will be written to: CTA_USER_DATA_DIR/analysis/<subarray>/EVNDISP/<particle>/

   "
   exit
fi

ARRAY=$1
RUNLIST=$2
PART=$3
DSET=$4
[[ "$5" ]] && KEEP=$5 || KEEP="0"
[[ "$6" ]] && FLL=$6 || FLL="0"
[[ "$7" ]] && QSUBOPT=$7 || QSUBOPT=""
QSUBOPT=${QSUBOPT//_X_/ }
QSUBOPT=${QSUBOPT//_M_/-}

# software paths
echo "CTA.EVNDISP.sub_convert_and_analyse_MC_VDST_ArrayJob $DSET"
source ../setSoftwarePaths.sh "$DSET"

# checking the path for binaries
if [ -z "$EVNDISPSYS" ]
then
    echo "no EVNDISPSYS env variable defined"
    exit
fi

# array list
if [ ! -e "${ARRAY}" ]; then
    echo "error: array list not found: ${ARRAY}"
    exit
fi

# skeleton script
FSCRIPT="CTA.EVNDISP.qsub_convert_and_analyse_MC_VDST_ArrayJob"

# output directory for shell scripts and run lists
# log files
QLOG="${CTA_USER_LOG_DIR%/}/jobs/$(uuidgen)"
SHELLDIR=${QLOG}
mkdir -p $QLOG
mkdir -p "$SHELLDIR"

########################
# production depedendent parameters
if [[ $DSET == *"prod3b"* ]]
then
    ARRAYCUTS="EVNDISP.prod3.reconstruction.runparameter.NN.LL"
    # calibration file with IPR graphs
    if [[ $DSET = *"paranal"* ]]
    then
       PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod3b/prod3b.Paranal-20171214.ped.root"
    elif [[ $DSET = *"LaPalma"* ]]
    then
       PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod3b/pedestal_nsb1x_LaPalma.root"
    else
       echo "Unknown data set for calibration file search with IPR graph"
       exit
    fi
elif [[ $DSET == *"prod4"* ]]
then
    ARRAYCUTS="EVNDISP.prod4.reconstruction.runparameter.NN.noLL"
    # calibration file with IPR graphs
    if [[ $DSET = *"SST"* ]]
    then
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod4/prod4b-SST-IPR.root"
    else
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod4/prod4b-MST-FlashCam.root"
    fi
elif [[ $DSET == *"prod5"* ]]
then
    ARRAYCUTS="EVNDISP.prod5.reconstruction.runparameter"
    if [[ $DSET == *"fullmoon"* ]] || [[ $DSET == *"NSB30x"* ]]; then
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod5/prod5-fullmoon-IPR.root"
    elif [[ $DSET == *"moon"* ]] || [[ $DSET == *"Moon"* ]] || [[ $DSET == *"NSB5x"* ]]; then
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod5/prod5-halfmoon-IPR.root"
    else
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod5/prod5-IPR.root"
    fi
elif [[ $DSET == *"prod6"* ]]
then
    ARRAYCUTS="EVNDISP.prod6.reconstruction.runparameter"
    ZE=$(echo $DSET | cut -d'-' -f3)
    if [[ $DSET == *"fullmoon"* ]]; then
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod6/prod6-full-ze${ZE}-IPR.root"
    elif [[ $DSET == *"moon"* ]] || [[ $DSET == *"Moon"* ]] || [[ $DSET == *"NSB5x"* ]]; then
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod6/prod6-half-ze${ZE}-IPR.root"
    else
        PEDFIL="$CTA_EVNDISP_AUX_DIR/Calibration/prod6/prod6-dark-ze${ZE}-IPR.root"
    fi
else
    echo "error: unknown production in $DSET"
    exit
fi

echo "PEDFIL: $PEDFIL"
if [ ! -e "$PEDFIL" ]
then
   echo "error: missing calibration file with IPR graphs"
   echo "$PEDFIL"
   exit
fi

########################################################
# get run list and number of runs
if [ ! -e "$RUNLIST" ]
then
  echo "list of sim_telarray files not found: $RUNLIST"
  exit
fi
RUNLISTN=$(basename "$RUNLIST")

#########################################################################3
# separate job for north and south
for D in 0 180
do

# run lists for north or south
    RUNLISTNdeg=$SHELLDIR/$RUNLISTN.$D.${DSET}
    rm -f "$RUNLISTNdeg"
    grep "_$D" "$RUNLIST" > "$RUNLISTNdeg"

    NRUN=$(wc -l "$RUNLISTNdeg" | awk '{print $1}')
    if [[ $NRUN = "0" ]]
    then
       if [[ $D = "0" ]]
       then
          grep north "$RUNLIST" > "$RUNLISTNdeg"
       else
          grep south "$RUNLIST" > "$RUNLISTNdeg"
       fi
       NRUN=$(wc -l $RUNLISTNdeg | awk '{print $1}')
    fi
    RUNFROMTO="1-$NRUN"
    NSTEP=1

    STEPSIZE=1
    let "NSTEP = $NRUN / $STEPSIZE"
    let "NTES  = $NSTEP * $STEPSIZE"
    if [[ $NTES -ne $NRUN ]]
    then
        let "NSTEP = $NSTEP + 1"
    fi
    RUNFROMTO="1-$NSTEP"

    echo "submitting $NRUN jobs ($NSTEP steps of size $STEPSIZE, $RUNFROMTO)"
    if [ "$NRUN" -eq 0 ]; then
        echo "No jobs for $D"
        continue
    fi

    FNAM="$SHELLDIR/$DSET-$PART-$FLL-$D"

    LIST=$(awk '{printf "%s ",$0} END {print ""}' "$ARRAY")

    sed -e "s|SIMTELLIST|$RUNLISTNdeg|" \
        -e "s|PAAART|$PART|" \
        -e "s!ARRAY!$LIST!" \
        -e "s|KEEEEEEP|$KEEP|" \
        -e "s|ARC|$ARRAYCUTS|" \
        -e "s|DATASET|$DSET|" \
        -e "s|FLL|$FLL|" \
        -e "s|PPPP|$PEDFIL|" \
        -e "s|STST|$STEPSIZE|" "$FSCRIPT.sh" > "$FNAM.sh"

    chmod u+x "$FNAM.sh"
    echo "$FNAM.sh"

    NUMDCAC=$(grep acs "$RUNLISTNdeg" | wc -l)
    DCACHEOPT=""
    # save dCache from heart attack
    if [[ $NUMDCAC -ge 1000 ]]
    then
        DCACHEOPT=" -l cta_dcache=1 "
    fi
    echo "DCACHEOPT $DCACHEOPT"

    if [[ $NRUN -ne 0 ]]
    then
        # SCT prod3 files need more memory:
        if [[ $DSET == "SCT" ]]
        then
            h_vmem="8G"
        fi
        if [[ $SUBC == *qsub* ]]; then
            qsub $QSUBOPT -t $RUNFROMTO:1 $DCACHEOPT -l h_cpu=${h_cpu} -l tmpdir_size=${tmpdir_size} -l h_rss=${h_vmem} -V -o "$QLOG" -e "$QLOG" "$FNAM.sh"
        elif [[ $SUBC == *condor* ]]; then
            ./condorSubmission.sh "${FNAM}.sh" $h_vmem $tmpdir_size $NSTEP
        fi
    echo "submit"
    fi
done

echo "submit script with $FNAM.sh"
echo "condor_submit $FNAM.sh.condor"
echo "writing queue log and error files to $QLOG"

exit
