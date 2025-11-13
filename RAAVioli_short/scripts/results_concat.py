import argparse
import pandas as pd
from os import listdir
parser = argparse.ArgumentParser()
parser.add_argument('-i', '--input', help='input directory with results')
parser.add_argument('-o', '--output', help='output path+bn', default="")
parser.add_argument('-a', '--assofile', help='asso file', default="")
args = parser.parse_args()
input_path = args.input
outputbn = args.output
assofile = args.assofile

assodf = pd.read_csv(assofile,sep="\t")
list_files = [x for x in listdir(input_path) if x.endswith("results.R1.tsv")]
assodf_tagid = assodf['TagID'].to_list()
res_df = []
for infile in list_files:
    tag = infile.split(".")[0]
    if tag in assodf_tagid:
        data = pd.read_csv(f'{input_path}/{infile}',sep="\t", dtype={'from_junc_to_plus20':'string','seq_gap':'string'})
        res_df.append(data)

if not res_df:
    raise ValueError("No results.R1.tsv files matched TagID entries. Check association file and pipeline outputs.")

appended_data = pd.concat(res_df, ignore_index=True)

appended_data.to_csv(outputbn,sep="\t",index=False)



