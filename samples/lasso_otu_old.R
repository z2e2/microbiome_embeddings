#!/usr/bin/env Rscript

library(tidyverse)
library(glmnet)
library(doMC)

dir_work <- '/mnt/HA/groups/rosenGrp/embed_ag_samples/out'

seed <- 3245
args <- commandArgs(trailingOnly=TRUE)

nc <- as.integer(args[1])

model <- file.path(dir_work,'ag_otu_table.rds')

path_out <- file.path(dir_work,'seqs_ag_otu_lasso.rds')
cat(sprintf('Output will be saved to %s\n.',path_out))

train_test <- readRDS(file.path(dir_work,'train_test_ids.rds'))

dat <- read_rds(file.path(dir_work,'ag_metadata.rds')) %>%
  select(PRIMARY_ID,body_site) %>%
  left_join(read_delim(file.path(dir_work,'ag_PRJEB11419.txt'),delim='\t') %>%
              select(PRIMARY_ID=secondary_sample_accession,SampleID=run_accession),
            by='PRIMARY_ID') %>%
  left_join(read_csv(file.path(dir_work,'ag_total_kmers.csv.gz')),by='SampleID') %>%
  filter(nreads >= 10000) %>%
  select(-PRIMARY_ID,-nreads) %>%
  filter(!is.na(body_site),
         body_site %in% c('UBERON:feces','UBERON:skin of hand','UBERON:skin of head','UBERON:tongue')) %>%
  mutate(body_site=as.character.factor(body_site),
         body_site=ifelse(body_site %in% c('UBERON:skin of hand','UBERON:skin of head'),'UBERON:skin',body_site)) %>%
  inner_join(readRDS(model))

train <- dat %>% filter(SampleID %in% train_test$train)
test <- dat %>% filter(SampleID %in% train_test$test)

cat(sprintf('Creating cluster with %s cores.\n',nc))
registerDoMC(nc)
cat('Performing lasso cross validation.\n')
set.seed(seed)

nf <- 10
cv <- cv.glmnet(train %>% select(-body_site,-SampleID) %>% as.matrix(),train$body_site,
                family='multinomial',type.measure='class',parallel=TRUE,
                standardize=FALSE,nfolds=nf)

y <- test$body_site
yhat <- as.vector(predict(cv,newx=test %>% select(-body_site,-SampleID) %>% as.matrix(),
                          type='class',s=cv$lambda.min))

out <- list(lasso=cv,train=train,test=test,results=data.frame(y=y,yhat=yhat))

cat('Saving results.\n')
saveRDS(out,path_out)

