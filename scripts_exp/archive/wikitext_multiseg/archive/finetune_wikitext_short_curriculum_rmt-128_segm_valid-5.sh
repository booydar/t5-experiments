#!/usr/bin/env bash
# CUDA_VISIBLE_DEVICES=1,2 NP=2 ./test_bert_sparse_pretrain_train_valid.sh
set -e
cd ../..

CUBLAS_WORKSPACE_CONFIG=:4096:2
CUDA_LAUNCH_BLOCKING=1

MODEL_TYPE=decoder
MODEL_CLS=modeling_rmt.language_modeling:RMTDecoderLMHeadMultiSeg
BACKBONE_CLS=transformers:AutoModelForCausalLM
TASK_NAME=wikitext-2-v1

ITERS=6000
TBS=32

TGT_LEN=128
INPUT_SIZE=128

MAX_N_SEGMENTSS=(3 4 5 6)
MEMORY_SIZES=(5 5 5 5 )
BSS=(4 2 2 2)

for N in 3
do

for MODEL_NAME in gpt2
do

for (( j=0; j<${#MEMORY_SIZES[@]}; j++ ))
do
MEMORY_SIZE=${MEMORY_SIZES[j]}
MAX_N_SEGMENTS=${MAX_N_SEGMENTSS[j]} 
INPUT_SEQ_LEN=$(((INPUT_SIZE-2*MEMORY_SIZE)*MAX_N_SEGMENTS))
BS=${BSS[j]}
LR=1e-05

K2=2

for SEGMENT_ORDERING in regular
do

for SCHEDULER in linear
do


echo RUNNING: TASK_NAME SRC_LEN MODEL_NAME MODEL_CLS N_SEG MEMORY_SIZE INPUT_SEQ_LEN LR N
echo RUNNING: $TASK_NAME $SRC_LEN $MODEL_NAME $MODEL_CLS $MAX_N_SEGMENTS $MEMORY_SIZE $INPUT_SEQ_LEN $LR $N
horovodrun --gloo -np $NP python run_finetuning_lm_multiseg_rmt_chunked.py \
        --task_name $TASK_NAME \
        --model_path ../runs/lm_long/${TASK_NAME}/$MODEL_NAME/${SCHEDULER}_adamw_wd1e-03_${INPUT_SEQ_LEN}-${TGT_LEN}-${MAX_N_SEGMENTS}x${INPUT_SIZE}_mem${MEMORY_SIZE}_bs${TBS}_${SEGMENT_ORDERING}_bptt-${K2}_from_cpt_$((MAX_N_SEGMENTS-1))-${MAX_N_SEGMENTS}_segm_valid/run_$N \
        --from_pretrained $MODEL_NAME \
        --model_type $MODEL_TYPE \
        --model_cls $MODEL_CLS \
        --model_cpt ../runs/lm_long/${TASK_NAME}/$MODEL_NAME/${SCHEDULER}_adamw_wd1e-03_$(((INPUT_SIZE-2*MEMORY_SIZE)*(MAX_N_SEGMENTS-1)))-${TGT_LEN}-$((MAX_N_SEGMENTS-1))x${INPUT_SIZE}_mem${MEMORY_SIZE}_bs${TBS}_${SEGMENT_ORDERING}_bptt-$((K2))_from_cpt_$((MAX_N_SEGMENTS-2))-$((MAX_N_SEGMENTS-1))_segm_valid/run_$N \
        --backbone_cls $BACKBONE_CLS \
        --input_seq_len $INPUT_SEQ_LEN \
        --input_size $INPUT_SIZE \
        --target_seq_len $TGT_LEN \
        --num_mem_tokens $MEMORY_SIZE \
        --max_n_segments $MAX_N_SEGMENTS\
        --batch_size $BS --gradient_accumulation_steps $(($TBS/($BS*$NP))) \
        --save_best \
        --iters $ITERS \
        --k1 -1 --k2 $K2 \
        --optimizer AdamW  --weight_decay 0.001 \
        --lr ${LR} --lr_scheduler $SCHEDULER --num_warmup_steps $(($ITERS/10)) \
        --data_n_workers 2 \
        --log_interval $(($ITERS/100)) --valid_interval $(($ITERS/10)) \
        --show_valid_examples 5 \
        --early_stopping_patience 15 \
        --seed $(($N+42)) \
        --clip_grad_value 5.0
        
done
done
done
done
done
done
done
echo "done"
