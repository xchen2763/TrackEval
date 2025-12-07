#!/bin/bash

# TrackEval Batch Evaluation Script - SurgVU Dataset
# Automatically runs evaluation for all seqmaps

# Setup color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration parameters
SEQMAPS_DIR="data_surgvu/ground_truth/seqmaps"
GT_FOLDER="data_surgvu/ground_truth"
TRACKERS_FOLDER="data_surgvu/tracking"
OUTPUT_FOLDER="data_surgvu/results"
BENCHMARK="MOT17"
SPLIT="train"
TRACKER="botsort"

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}TrackEval Batch Evaluation - SurgVU Dataset${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Check if seqmaps directory exists
if [ ! -d "$SEQMAPS_DIR" ]; then
    echo -e "${RED}Error: Seqmaps directory not found: $SEQMAPS_DIR${NC}"
    exit 1
fi

# Track success and failure counts
SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

# Create results directory
mkdir -p "$OUTPUT_FOLDER"

# Iterate through all seqmap files
echo -e "${YELLOW}Searching for seqmap files...${NC}"
echo ""

for seqmap_file in "$SEQMAPS_DIR"/*.txt; do
    # Check if file exists (prevent case where no files match)
    if [ ! -f "$seqmap_file" ]; then
        echo -e "${RED}No seqmap files found${NC}"
        exit 1
    fi
    
    # Get filename (without path)
    filename=$(basename "$seqmap_file")
    
    # Extract tool type from filename
    # Example: MOT17-train-cautery_hook.txt -> cautery_hook
    tool_name=$(echo "$filename" | sed 's/MOT17-train-//' | sed 's/\.txt$//')
    
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    echo -e "${GREEN}[$TOTAL_COUNT]${NC} Processing: ${YELLOW}$filename${NC}"
    echo -e "    Tool type: ${YELLOW}$tool_name${NC}"
    echo -e "    Seqmap file: $seqmap_file"
    echo ""
    
    # Run evaluation
    echo -e "${YELLOW}    Starting evaluation...${NC}"
    
    python scripts/run_mot_challenge.py \
        --BENCHMARK "$BENCHMARK" \
        --SPLIT_TO_EVAL "$SPLIT" \
        --TRACKERS_TO_EVAL "$TRACKER" \
        --CLASSES_TO_EVAL "$tool_name" \
        --GT_FOLDER "$GT_FOLDER" \
        --TRACKERS_FOLDER "$TRACKERS_FOLDER" \
        --OUTPUT_FOLDER "$OUTPUT_FOLDER" \
        --SEQMAP_FILE "$seqmap_file" \
        --OUTPUT_SUB_FOLDER "$tool_name"
    
    # Check if command succeeded
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}    ✓ Evaluation successful: $tool_name${NC}"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "${RED}    ✗ Evaluation failed: $tool_name${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
    echo "----------------------------------------"
    echo ""
done

# Print summary
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Evaluation Summary${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "Total: $TOTAL_COUNT tool types"
echo -e "${GREEN}Success: $SUCCESS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
else
    echo -e "Failed: $FAIL_COUNT"
fi
echo ""
echo -e "Results saved to: ${YELLOW}$OUTPUT_FOLDER${NC}"
echo ""

# List generated result files
echo -e "${YELLOW}Generated result files:${NC}"
find "$OUTPUT_FOLDER" -name "*_summary.txt" -o -name "*_detailed.csv" | sort

echo ""
echo -e "${YELLOW}Generating summary CSV...${NC}"

# Create summary CSV
SUMMARY_CSV="$OUTPUT_FOLDER/$TRACKER/trackeval_summary_surgvu.csv"
echo "Tool,HOTA,DetA,AssA,IDSW,Frag,Dets,Time_min,IDSW_per_min,Frag_per_min" > "$SUMMARY_CSV"

# SurgVU: Detection frequency is every 1 second, so T (minutes) = Dets / 60

# Get all tool types dynamically from the results directory
for tool_dir in "$OUTPUT_FOLDER/$TRACKER"/*/; do
    if [ -d "$tool_dir" ]; then
        tool=$(basename "$tool_dir")
        summary_file="$tool_dir/${tool}_summary.txt"
        
        if [ -f "$summary_file" ]; then
            # Read header and data lines
            header=$(head -1 "$summary_file")
            data=$(tail -1 "$summary_file")
            
            # Convert to arrays
            IFS=' ' read -ra HEADERS <<< "$header"
            IFS=' ' read -ra VALUES <<< "$data"
            
            # Find indices for required metrics
            hota_idx=-1
            deta_idx=-1
            assa_idx=-1
            idsw_idx=-1
            frag_idx=-1
            dets_idx=-1
            
            for i in "${!HEADERS[@]}"; do
                case "${HEADERS[$i]}" in
                    "HOTA") hota_idx=$i ;;
                    "DetA") deta_idx=$i ;;
                    "AssA") assa_idx=$i ;;
                    "IDSW") idsw_idx=$i ;;
                    "Frag") frag_idx=$i ;;
                    "Dets") dets_idx=$i ;;
                esac
            done
            
            # Extract values
            hota_val=${VALUES[$hota_idx]:-"N/A"}
            deta_val=${VALUES[$deta_idx]:-"N/A"}
            assa_val=${VALUES[$assa_idx]:-"N/A"}
            idsw_val=${VALUES[$idsw_idx]:-"0"}
            frag_val=${VALUES[$frag_idx]:-"0"}
            dets_val=${VALUES[$dets_idx]:-"1"}
            
            # Calculate time in minutes: T = Dets / 60 (detection every 1 second)
            time_min=$(awk "BEGIN {printf \"%.3f\", $dets_val / 60}")
            
            # Calculate normalized metrics: IDSW_per_min = IDSW / T, Frag_per_min = Frag / T
            idsw_per_min=$(awk "BEGIN {if ($dets_val > 0) printf \"%.3f\", $idsw_val / ($dets_val / 60); else print \"0\"}")
            frag_per_min=$(awk "BEGIN {if ($dets_val > 0) printf \"%.3f\", $frag_val / ($dets_val / 60); else print \"0\"}")
            
            # Write to CSV
            echo "$tool,$hota_val,$deta_val,$assa_val,$idsw_val,$frag_val,$dets_val,$time_min,$idsw_per_min,$frag_per_min" >> "$SUMMARY_CSV"
        else
            echo "$tool,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A" >> "$SUMMARY_CSV"
        fi
    fi
done

echo -e "${GREEN}Summary CSV generated: ${SUMMARY_CSV}${NC}"
echo ""
echo -e "${YELLOW}Summary table:${NC}"
column -t -s',' "$SUMMARY_CSV"

exit 0

