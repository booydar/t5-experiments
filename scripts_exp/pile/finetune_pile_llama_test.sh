#!/usr/bin/env bash
# CUDA_VISIBLE_DEVICES=1,2 NP=2 ./test_bert_sparse_pretrain_train_valid.sh
set -e
cd ../..

CUBLAS_WORKSPACE_CONFIG=:4096:2
CUDA_LAUNCH_BLOCKING=1

MODEL_TYPE=decoder
MEMORY_CELL=modeling_rmt.language_modeling:MemoryCell
RECURRENT_WRAPPER=modeling_rmt.language_modeling:RecurrentWrapper
BACKBONE_CLS=base_models.modeling_llama:LlamaForCausalLM
TASK_NAME=pile

ITERS=50000
TBS=256

INPUT_SIZE=2048

MAX_N_SEGMENTSS=(1)
BSS=(1)

for MEMORY_SIZE in 0
do 

for N in 1
do

for MODEL_NAME in meta-llama/Llama-2-7b-hf
do

for (( j=0; j<${#MAX_N_SEGMENTSS[@]}; j++ ))
do
MAX_N_SEGMENTS=${MAX_N_SEGMENTSS[j]} 
BLOCK_SIZE=$((INPUT_SIZE-2*MEMORY_SIZE))
HISTORY_SIZE=$(((MAX_N_SEGMENTS - 1) * BLOCK_SIZE))
BS=${BSS[j]}
K2=${MAX_N_SEGMENTS}

LR=1e-04

for SEGMENT_ORDERING in regular
do

for SCHEDULER in linear
do


GRAD_ACC_STEPS=$(($TBS/($BS*$NP)))
SAMPLING_PROB=1


NP=$NP
ACCEL_CONFIG=./accel_configs/exp/accelerate/deepspeed_bf16_tbs${TBS}bs${BS}g${GRAD_ACC_STEPS}c1.0np${NP}.yaml
cd accel_configs/
python create_config.py \
        --bf16 \
        --train_batch_size $TBS\
        --train_micro_batch_size_per_gpu $BS\
        --gradient_accumulation_steps $GRAD_ACC_STEPS\
        --np $NP\
        --gradient_clipping 1.0
cd ..

for SEGMENT_ORDERING in regular
do

for SCHEDULER in linear
do


echo RUNNING: TASK_NAME MEMORY_SIZE INPUT_SIZE BLOCK_SIZE HISTORY_SIZE N_SEG  MODEL_NAME MODEL_CLS LR N
echo RUNNING: $TASK_NAME $MEMORY_SIZE $INPUT_SIZE $BLOCK_SIZE $HISTORY_SIZE $MAX_N_SEGMENTS $MODEL_NAME $MODEL_CLS  $LR $N
echo gradient accumulation steps $GRAD_ACC_STEPS
accelerate launch --config_file $ACCEL_CONFIG --main_process_port 29522 run_finetuning_pile_rmt_llama.py \
        --task_name $TASK_NAME \
        --model_path ../runs/test/${TASK_NAME}/$MODEL_NAME/lr${LR}_${SCHEDULER}_adamw_wd1e-03_${BLOCK_SIZE}-${HISTORY_SIZE}-${MAX_N_SEGMENTS}x${INPUT_SIZE}_mem${MEMORY_SIZE}_bs${TBS}_${SEGMENT_ORDERING}_bptt-${K2}_sp${SAMPLING_PROB}_lora_test/run_$N \
        --from_pretrained $MODEL_NAME \
        --model_type $MODEL_TYPE \
        --memory_cell_cls $MEMORY_CELL \
        --recurrent_wrapper_cls $RECURRENT_WRAPPER \
        --model_cls $BACKBONE_CLS \
        --block_size $BLOCK_SIZE \
        --history_size $HISTORY_SIZE \
        --sampling_prob $SAMPLING_PROB \
        --input_size $INPUT_SIZE \
        --num_mem_tokens $MEMORY_SIZE \
        --max_n_segments $MAX_N_SEGMENTS\
        --vary_n_segments \
        --min_tokens_in_document 2040 \
        --batch_size $BS --gradient_accumulation_steps $(($TBS/($BS*$NP))) \
        --num_training_steps $((ITERS*2)) \
        --iters $ITERS \
        --k2 $K2 \
        --use_lora \
        --use_flash_attention \
        --freeze_model_weights \
        --lora_attn_alpha 32 \
        --lora_dropout 0.05 \
        --lora_attn_dim 8 \
        --optimizer AdamW  --weight_decay 0.01 \
        --lr ${LR} --lr_scheduler $SCHEDULER --num_warmup_steps $(($ITERS/10)) \
        --data_n_workers 2 \
        --log_interval $(($ITERS/100)) --valid_interval $(($ITERS/20)) \
        --show_valid_examples 5 \
        --early_stopping_patience 15 \
        --seed $(($N+42)) \
        --clip_grad_norm 1.0
        
done
done
done
done
done
done
done
done
echo "done"
