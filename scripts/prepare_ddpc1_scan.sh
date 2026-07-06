#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWEEP_DIR="${SWEEP_DIR:-$ROOT/jobs/sweep_btv_dtv}"
TEMPLATE_INPUT="${1:-$ROOT/dirqfam.dat}"

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
JOB_NAME_PREFIX="${JOB_NAME_PREFIX:-Yb160_K0}"

INPUTS_DIR="$SWEEP_DIR/inputs"
RUNS_DIR="$SWEEP_DIR/runs"
MANIFEST="$SWEEP_DIR/manifest.tsv"

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

mkdir -p "$INPUTS_DIR" "$RUNS_DIR"
cp "$ROOT/run" "$INPUTS_DIR/run"
cp "$TEMPLATE_INPUT" "$INPUTS_DIR/dirqfam.dat"

printf "task_id\tb_TV\td_TV\trun_label\trun_dir\tparams_file\n" > "$MANIFEST"

task_id=0
for ((ib=0; ib<B_N; ib++)); do
  b_tv="$(format_value "$(grid_value "$B_MIN" "$B_MAX" "$B_N" "$ib")")"
  b_label="btv_$(path_value "$b_tv")"

  for ((id=0; id<D_N; id++)); do
    d_tv="$(format_value "$(grid_value "$D_MIN" "$D_MAX" "$D_N" "$id")")"
    d_label="dtv_$(path_value "$d_tv")"
    run_dir="$RUNS_DIR/${b_label}_${d_label}"
    params_file="$run_dir/params.yaml"

    mkdir -p "$run_dir/output/GS_output" "$run_dir/output/QFAM_output" "$run_dir/logs"

    cat > "$params_file" <<EOF
b_TV: $b_tv
d_TV: $d_tv
run_label: ${b_label}_${d_label}
EOF

    run_label="${b_label}_${d_label}"
    printf "%d\t%s\t%s\t%s\t%s\t%s\n" "$task_id" "$b_tv" "$d_tv" "$run_label" "$run_dir" "$params_file" >> "$MANIFEST"
    task_id=$((task_id + 1))
  done
done

last_task=$((task_id - 1))
cat > "$SWEEP_DIR/submit_array.slurm" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${JOB_NAME_PREFIX}_btv_dtv_strength
#SBATCH --output=/dev/null
#SBATCH --error=/dev/null
#SBATCH --time=$TIME_LIMIT
#SBATCH --partition=$PARTITION
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=$CPUS_PER_TASK
#SBATCH --mem-per-cpu=$MEM_PER_CPU
#SBATCH --array=0-$last_task

set -euo pipefail

module purge
module load GCC/12.3.0
module load OpenBLAS/0.3.23-GCC-12.3.0

export OPENBLAS_NUM_THREADS="\${OPENBLAS_NUM_THREADS:-\$SLURM_CPUS_PER_TASK}"
export OMP_NUM_THREADS="\${OMP_NUM_THREADS:-\$SLURM_CPUS_PER_TASK}"
export MKL_NUM_THREADS="\${MKL_NUM_THREADS:-\$SLURM_CPUS_PER_TASK}"

MANIFEST="$MANIFEST"
INPUTS_DIR="$INPUTS_DIR"

row="\$(awk -v task_id="\$SLURM_ARRAY_TASK_ID" 'NR > 1 && \$1 == task_id { print; exit }' "\$MANIFEST")"
if [[ -z "\$row" ]]; then
  echo "No manifest row found for SLURM_ARRAY_TASK_ID=\$SLURM_ARRAY_TASK_ID" >&2
  exit 1
fi

IFS=\$'\t' read -r task_id b_tv d_tv run_label run_dir params_file <<< "\$row"

job_name="${JOB_NAME_PREFIX}_\${run_label}_strength"
if command -v scontrol >/dev/null 2>&1; then
  scontrol update JobId="\$SLURM_JOB_ID" JobName="\$job_name" || true
fi

mkdir -p "\$run_dir/output/GS_output" "\$run_dir/output/QFAM_output" "\$run_dir/logs"

log_base="\$run_dir/logs/\${job_name}_\${SLURM_ARRAY_JOB_ID}_\${SLURM_ARRAY_TASK_ID}"
exec > "\${log_base}.out" 2> "\${log_base}.err"

echo "job_name: \$job_name"
echo "task_id: \$task_id"
echo "b_TV: \$b_tv"
echo "d_TV: \$d_tv"
echo "run_dir: \$run_dir"

cp "\$INPUTS_DIR/dirqfam.dat" "\$run_dir/dirqfam.dat"
cat > "\$run_dir/ddpc1_scan.in" <<PARAMS
# Format: b_TV d_TV
# Generated at runtime from \$params_file
\$b_tv \$d_tv
PARAMS

cd "\$run_dir"
"\$INPUTS_DIR/run"
EOF
chmod +x "$SWEEP_DIR/submit_array.slurm"

echo "Prepared $task_id run directories under $SWEEP_DIR"
echo "Manifest: $MANIFEST"
echo "Single-point test:"
echo "  sbatch --array=0-0 \"$SWEEP_DIR/submit_array.slurm\""
echo "Array submission after the single point works:"
echo "  sbatch \"$SWEEP_DIR/submit_array.slurm\""
