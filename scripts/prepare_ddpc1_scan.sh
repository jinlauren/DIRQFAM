#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_INPUT="${1:-$ROOT/templates/dirqfam.dat}"

SCAN_NAME="${SCAN_NAME:-scan_btv_dtv_test}"
NUCLEUS="${NUCLEUS:-Yb160}"
K_LABEL="${K_LABEL:-K0}"
CALC_TYPE="${CALC_TYPE:-strength}"
SCAN_ROOT="${SCAN_ROOT:-$ROOT/runs/$SCAN_NAME/$K_LABEL/$CALC_TYPE}"

B_MIN="${B_MIN:-1.0}"
B_MAX="${B_MAX:-4.5}"
D_MIN="${D_MIN:-0.2}"
D_MAX="${D_MAX:-2.0}"
B_N="${B_N:-15}"
D_N="${D_N:-15}"

CPUS_PER_TASK="${CPUS_PER_TASK:-6}"
MEM_PER_CPU="${MEM_PER_CPU:-10G}"
TIME_LIMIT="${TIME_LIMIT:-10:00:00}"
PARTITION="${PARTITION:-general-long}"
format_value() {
  awk -v x="$1" 'BEGIN { printf "%.4f", int(x*1000 + 0.5)/1000 }'
}

path_value() {
  local value
  value="$(format_value "$1")"
  value="${value//-/m}"
  value="${value//./p}"
  echo "$value"
}

grid_value() {
  local min="$1"
  local max="$2"
  local n="$3"
  local i="$4"
  awk -v min="$min" -v max="$max" -v n="$n" -v i="$i" \
    'BEGIN {
      if (n < 1) exit 2;
      if (n == 1) printf "%.12g", min;
      else printf "%.12g", min + i*(max-min)/(n-1);
    }'
}

if [[ ! -x "$ROOT/run" ]]; then
  echo "Missing executable: $ROOT/run" >&2
  echo "Build it first with: make run" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_INPUT" ]]; then
  echo "Missing DIRQFAM input template: $TEMPLATE_INPUT" >&2
  exit 1
fi
TEMPLATE_INPUT="$(cd "$(dirname "$TEMPLATE_INPUT")" && pwd)/$(basename "$TEMPLATE_INPUT")"

mkdir -p "$SCAN_ROOT"
MANIFEST="$SCAN_ROOT/manifest.tsv"
ARRAY_LOG_DIR="$SCAN_ROOT/array_logs"
mkdir -p "$ARRAY_LOG_DIR"
printf "task_id\tb_TV\td_TV\trun_label\trun_dir\tslurm_script\tmetadata_file\n" > "$MANIFEST"

task_id=0
for ((ib=0; ib<B_N; ib++)); do
  b_tv="$(format_value "$(grid_value "$B_MIN" "$B_MAX" "$B_N" "$ib")")"
  b_label="btv_$(path_value "$b_tv")"

  for ((id=0; id<D_N; id++)); do
    d_tv="$(format_value "$(grid_value "$D_MIN" "$D_MAX" "$D_N" "$id")")"
    d_label="dtv_$(path_value "$d_tv")"
    run_label="${b_label}_${d_label}"
    run_dir="$SCAN_ROOT/$run_label"
    slurm_script="$run_dir/run.slurm"
    metadata_file="$run_dir/metadata.yaml"

    mkdir -p "$run_dir/output/GS_output" "$run_dir/output/QFAM_output" "$run_dir/logs"

    cat > "$metadata_file" <<EOF
scan_name: $SCAN_NAME
nucleus: $NUCLEUS
k_label: $K_LABEL
calculation_type: $CALC_TYPE
run_label: $run_label
b_TV: $b_tv
d_TV: $d_tv
template_input: $TEMPLATE_INPUT
slurm_script: $slurm_script
output_dir: $run_dir/output
logs_dir: $run_dir/logs
EOF

    job_name="${NUCLEUS}_${K_LABEL}_${run_label}_${CALC_TYPE}"
    cat > "$slurm_script" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=$job_name
#SBATCH --output=logs/%j.out
#SBATCH --error=logs/%j.err
#SBATCH --time=$TIME_LIMIT
#SBATCH --partition=$PARTITION
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$CPUS_PER_TASK
#SBATCH --mem-per-cpu=$MEM_PER_CPU

set -euo pipefail

module purge
module load GCC/12.3.0
module load OpenBLAS/0.3.23-GCC-12.3.0

export OMP_NUM_THREADS="\$SLURM_CPUS_PER_TASK"
export OPENBLAS_NUM_THREADS="\$SLURM_CPUS_PER_TASK"
export MKL_NUM_THREADS="\$SLURM_CPUS_PER_TASK"

cd "\$SLURM_SUBMIT_DIR"
mkdir -p output/GS_output output/QFAM_output logs

cp "$TEMPLATE_INPUT" dirqfam.dat
cat > ddpc1_scan.in <<PARAMS
# Format: b_TV d_TV
$b_tv $d_tv
PARAMS

"$ROOT/run"
EOF
    chmod +x "$slurm_script"

    printf "%d\t%s\t%s\t%s\t%s\t%s\t%s\n" "$task_id" "$b_tv" "$d_tv" "$run_label" "$run_dir" "$slurm_script" "$metadata_file" >> "$MANIFEST"
    task_id=$((task_id + 1))
  done
done

last_task=$((task_id - 1))
cat > "$SCAN_ROOT/submit_array.slurm" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${NUCLEUS}_${K_LABEL}_${SCAN_NAME}_${CALC_TYPE}
#SBATCH --output=$ARRAY_LOG_DIR/%A_%a.out
#SBATCH --error=$ARRAY_LOG_DIR/%A_%a.err
#SBATCH --time=$TIME_LIMIT
#SBATCH --partition=$PARTITION
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$CPUS_PER_TASK
#SBATCH --mem-per-cpu=$MEM_PER_CPU
#SBATCH --array=0-$last_task

set -euo pipefail

MANIFEST="$MANIFEST"
RUN_EXE="$ROOT/run"
TEMPLATE_INPUT="$TEMPLATE_INPUT"

row="\$(awk -v task_id="\$SLURM_ARRAY_TASK_ID" 'NR > 1 && \$1 == task_id { print; exit }' "\$MANIFEST")"
if [[ -z "\$row" ]]; then
  echo "No manifest row found for SLURM_ARRAY_TASK_ID=\$SLURM_ARRAY_TASK_ID" >&2
  exit 1
fi

IFS=\$'\t' read -r task_id b_tv d_tv run_label run_dir slurm_script metadata_file <<< "\$row"

job_name="${NUCLEUS}_${K_LABEL}_\${run_label}_${CALC_TYPE}"

mkdir -p "\$run_dir/output/GS_output" "\$run_dir/output/QFAM_output" "\$run_dir/logs"
log_base="\$run_dir/logs/\${job_name}_\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}"
exec > "\${log_base}.out" 2> "\${log_base}.err"

if [[ -n "\${SLURM_JOB_ID:-}" ]] && command -v scontrol >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  timeout 5s scontrol update JobId="\$SLURM_JOB_ID" JobName="\$job_name" || true
fi

echo "job_name: \$job_name"
echo "task_id: \$task_id"
echo "b_TV: \$b_tv"
echo "d_TV: \$d_tv"
echo "run_label: \$run_label"
echo "run_dir: \$run_dir"
echo "metadata_file: \$metadata_file"

module purge
module load GCC/12.3.0
module load OpenBLAS/0.3.23-GCC-12.3.0

export OMP_NUM_THREADS="\$SLURM_CPUS_PER_TASK"
export OPENBLAS_NUM_THREADS="\$SLURM_CPUS_PER_TASK"
export MKL_NUM_THREADS="\$SLURM_CPUS_PER_TASK"

cd "\$run_dir"

cp "\$TEMPLATE_INPUT" dirqfam.dat
cat > ddpc1_scan.in <<PARAMS
# Format: b_TV d_TV
\$b_tv \$d_tv
PARAMS

"\$RUN_EXE"
EOF
chmod +x "$SCAN_ROOT/submit_array.slurm"

echo "Prepared $task_id calculation directories under $SCAN_ROOT"
echo "Manifest: $MANIFEST"
echo "Single-point test:"
echo "  cd \"$(awk 'NR==2 { print $5 }' "$MANIFEST")\""
echo "  sbatch \"$(awk 'NR==2 { print $6 }' "$MANIFEST")\""
echo "Array submission:"
echo "  sbatch \"$SCAN_ROOT/submit_array.slurm\""
