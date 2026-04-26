"""Patch DeepLab dataset file to support RV's 'custom' dataset."""
import os
import glob

# Find the right file (data_generator.py or segmentation_dataset.py)
candidates = glob.glob('/opt/tf-models/research/deeplab/datasets/data_generator.py') + \
             glob.glob('/opt/tf-models/research/deeplab/datasets/segmentation_dataset.py')

for path in candidates:
    with open(path) as f:
        code = f.read()

    if '_DATASETS_INFORMATION' not in code:
        continue

    print(f'Patching: {path}')

    if 'import os' not in code:
        code = 'import os\n' + code

    custom_entry = """    'custom': DatasetDescriptor(
        splits_to_sizes={
            'train': int(os.environ.get('DL_CUSTOM_TRAIN', 0)),
            'validation': int(os.environ.get('DL_CUSTOM_VALIDATION', 0)),
        },
        num_classes=int(os.environ.get('DL_CUSTOM_CLASSES', 3)),
        ignore_label=255,
    ),
"""

    # Try different markers depending on version
    patched = False
    for marker in ["'ade20k': _ADE20K_INFORMATION,",
                   "'pascal_voc_seg': _PASCAL_VOC_SEG_INFORMATION,"]:
        if marker in code:
            code = code.replace(marker, marker + '\n' + custom_entry)
            patched = True
            print(f'  Inserted after: {marker}')
            break

    if not patched:
        print('  WARNING: Could not find marker, using fallback')
        code = code.replace('}\n\n', custom_entry + '}\n\n', 1)

    with open(path, 'w') as f:
        f.write(code)

    print(f'  Done: {path}')
    break
else:
    print('ERROR: No dataset file found to patch!')
    exit(1)
