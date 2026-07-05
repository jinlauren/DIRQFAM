#!/bin/bash
#SBATCH --job-name=Yb160_K0_strength
#SBATCH --output=slurm/logs/Yb160_K0_strength_%j.out
#SBATCH --error=slurm/logs/Yb160_K0_strength_%j.err
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=40
#SBATCH --mem=10G

module purge
module load GCC/12.3.0
module load OpenBLAS/0.3.23-GCC-12.3.0

export OPENBLAS_NUM_THREADS=$SLURM_CPUS_PER_TASK

ROOT="$SLURM_SUBMIT_DIR"
CALC="Yb160_K0_strength"

OUTDIR="$ROOT/output/$CALC"
WORKDIR="$ROOT/slurm/work_${CALC}_${SLURM_JOB_ID}"

mkdir -p "$OUTDIR/GS_output" "$OUTDIR/QFAM_output"
mkdir -p "$WORKDIR/output"

ln -s "$OUTDIR/GS_output" "$WORKDIR/output/GS_output"
ln -s "$OUTDIR/QFAM_output" "$WORKDIR/output/QFAM_output"
ln -s "$ROOT/run" "$WORKDIR/run"

cp "$ROOT/slurm/inputs/${CALC}.dat" "$WORKDIR/dirqfam.dat"

cd "$WORKDIR"

./run
