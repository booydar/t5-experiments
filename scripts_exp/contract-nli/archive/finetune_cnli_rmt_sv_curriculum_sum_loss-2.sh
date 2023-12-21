#!/usr/bin/env bash
# CUDA_VISIBLE_DEVICES=1,2 NP=2 ./test_bert_sparse_pretrain_train_valid.sh
set -e
cd ../..

CUBLAS_WORKSPACE_CONFIG=:4096:2
CUDA_LAUNCH_BLOCKING=1

MODEL_TYPE=encoder
BACKBONE_CLS=transformers:AutoModelForSequenceClassification
TASK_NAME=contract_nli
METRIC=exact_match

ITERS=4000
TBS=32

TGT_LEN=512
MODEL_INPUT_SIZE=512

INPUT_SEQ_LENS=(1996 2497)
MAX_N_SEGMENTSS=(4 5)
MEMORY_SIZES=(10 10)
BSS=(2 1)

for N in 1
do

for MODEL_NAME in bert-base-cased 
do

for (( j=0; j<${#MEMORY_SIZES[@]}; j++ ))
do
MEMORY_SIZE=${MEMORY_SIZES[j]}
MAX_N_SEGMENTS=${MAX_N_SEGMENTSS[j]} 
INPUT_SEQ_LEN=${INPUT_SEQ_LENS[j]}
BS=${BSS[j]}

for SEGMENT_ORDERING in regular
do

SCHEDULER=linear

for LR in 1e-05
do

MODEL_CLS=modeling_rmt:RMTEncoderForSequenceClassification

echo RUNNING: TASK_NAME SRC_LEN MODEL_NAME MODEL_CLS N_SEG MEMORY_SIZE INPUT_SEQ_LEN LR N
echo RUNNING: $TASK_NAME $SRC_LEN $MODEL_NAME $MODEL_CLS $MAX_N_SEGMENTS $MEMORY_SIZE $INPUT_SEQ_LEN $LR $N
horovodrun --gloo -np $NP python run_finetuning_scrolls_rmt.py \
        --task_name $TASK_NAME \
        --model_path ../runs/curriculum/${TASK_NAME}/$MODEL_NAME/lr${LR}_${SCHEDULER}_adamw_wd1e-03_${INPUT_SEQ_LEN}-${TGT_LEN}-{$MAX_N_SEGMENTS}seg_mem${MEMORY_SIZE}_bs${TBS}_iters${ITERS}_${SEGMENT_ORDERING}_sum_loss_from_cpt_$((MAX_N_SEGMENTS-1))-${MAX_N_SEGMENTS}/run_$N \
        --from_pretrained $MODEL_NAME \
        --model_type $MODEL_TYPE \
        --model_cls $MODEL_CLS \
        --model_cpt ../runs/curriculum/${TASK_NAME}/$MODEL_NAME/lr1e-05_linear_adamw_wd1e-03_$((INPUT_SEQ_LEN-499))-${TGT_LEN}-{$((MAX_N_SEGMENTS-1))}seg_mem${MEMORY_SIZE}_bs${TBS}_iters8000_${SEGMENT_ORDERING}_sum_loss_from_cpt_$((MAX_N_SEGMENTS-2))-$((MAX_N_SEGMENTS-1))/run_$N \
        --backbone_cls $BACKBONE_CLS \
        --input_seq_len $INPUT_SEQ_LEN \
        --input_size $MODEL_INPUT_SIZE \
        --target_seq_len $TGT_LEN \
        --num_mem_tokens $MEMORY_SIZE \
        --max_n_segments $MAX_N_SEGMENTS \
        --segment_ordering $SEGMENT_ORDERING \
        --sum_loss \
        --bptt_depth -1 \
        --batch_size $BS --gradient_accumulation_steps $(($TBS/($BS*$NP))) \
        --iters $ITERS \
        --optimizer AdamW  --weight_decay 0.001 \
        --lr ${LR} --lr_scheduler $SCHEDULER --num_warmup_steps $(($ITERS/10)) \
        --data_n_workers 2 \
        --log_interval $(($ITERS/100)) --valid_interval $(($ITERS/10)) \
        --optimize_metric $METRIC --optimize_mode max \
        --show_valid_examples 5 \
        --early_stopping_patience 15 \
        --optimize_metric $METRIC --optimize_mode max \
        --seed $(($N+42)) \
        --clip_grad_value 5.0
        
done
done
done
done
done
echo "done"
