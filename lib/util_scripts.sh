## Date:        1st of November 2022
## Description: 

reportCmdTiming()
{
    timestampInit=$(date +%s);
    dateInit=$(date);
    echo "Started '$dateInit'";
    
    eval $@;
    res=$?;

    echo "reportCmdTiming REPORT:"
    echo "    Started '$dateInit'";
    echo "    Finished '$(date)'";
    timestampEnd=$(date +%s);
    echo "    Elapsed $(expr $timestampEnd - $timestampInit) seconds.";
    echo "    Result: $res";

    return $res;
}

ringBellAndSetExitCode()
{
    tput bel;
    res=${1:-1};
    return $res;
}

