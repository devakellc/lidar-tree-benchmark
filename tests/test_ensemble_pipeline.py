"""Full-row instance products, pooling and frozen reserve policy checks."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import laspy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_ensemble_pipeline as pipeline


class PipelineTests(unittest.TestCase):
    def test_invalid_output_locations_cannot_start_inference(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; root.mkdir()
            prepared=base/'prepared'; prepared.mkdir()
            run=base/'run'
            for out in (prepared/'products', run, run/'products', base/'missing/products'):
                with self.subTest(out=out), mock.patch.object(pipeline.reserve, 'run') as execute:
                    with self.assertRaises(ValueError):
                        pipeline.assemble(root, 'reserve', prepared, run, out, execute=True)
                    execute.assert_not_called()

    def test_reserve_fusion_override_fails_before_any_parent_or_point_read(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; root.mkdir()
            with self.assertRaisesRegex(ValueError, 'policy is frozen'):
                pipeline.assemble(root, 'reserve', base/'prepared', base/'run', base/'out', 'union_all')

    def test_mask_product_preserves_background_rows_and_original_ids(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); geometry=base/'inputs'; geometry.mkdir()
            source=base/'run'; (source/'model_io').mkdir(parents=True)
            out=base/'products'; out.mkdir()
            h=laspy.LasHeader(point_format=7,version='1.4')
            h.add_extra_dim(laspy.ExtraBytesParams(name='source_row',type='uint32'))
            raw=laspy.LasData(h)
            raw.x=np.zeros(84); raw.y=np.zeros(84)
            raw.z=np.r_[np.linspace(0,5,40),np.linspace(0,5,39),np.zeros(5)]
            raw.source_row=np.arange(84,dtype='uint32')*2
            raw.return_number=np.ones(84,dtype='uint8'); raw.number_of_returns=raw.return_number
            raw.classification=np.ones(84,dtype='uint8')
            raw.write(geometry/'geometry.las'); raw.write(geometry/'normalized.laz')
            pred=laspy.LasData(raw.header.copy(),raw.points.copy())
            pred.add_extra_dim(laspy.ExtraBytesParams(name='ff3d_row',type='uint32'))
            pred.add_extra_dim(laspy.ExtraBytesParams(name='ff3d_score',type='float32'))
            pred.ff3d_row=np.arange(84); pred.point_source_id=np.r_[[7]*40,[8]*39,[0]*5]
            pred.ff3d_score=np.where(pred.point_source_id>0,.6,0)
            pred.write(source/'model_io/predictions.laz')
            labels=np.r_[[7]*40,[0]*44]
            np.savetxt(source/'prediction_labels.csv',labels,fmt='%d',header='pred_instance',comments='')
            receipt=pipeline.export_instances(geometry,source,out)
            self.assertEqual(receipt['instances'],1)
            saved=laspy.read(out/'instance_masks.laz')
            np.testing.assert_array_equal(saved.source_row,raw.source_row)
            np.testing.assert_array_equal(saved.pred_instance,labels)
            self.assertNotIn('tree_index',saved.point_format.dimension_names)
            labels[-1]=7
            np.savetxt(source/'prediction_labels.csv',labels,fmt='%d',header='pred_instance',comments='')
            with self.assertRaisesRegex(ValueError,'admitted fixed filter'):
                pipeline.export_instances(geometry,source,out)

    def test_pooling_uses_counts_and_mask_sums_not_per_plot_rates(self):
        cells=[]
        for plot,tp,fp,fn,si,sm in [('1003',1,0,0,.6,.7),('1010',3,1,6,1.8,2.0)]:
            mask=dict(TP=tp,FP=fp,FN=fn,n_pred=tp+fp,n_ref=tp+fn,sum_iou=si,sum_maxiou=sm)
            for c in 'ABCD':
                mask.update({k+c:v if c=='A' else 0 for k,v in
                    [('n_',tp+fn),('tp_',tp),('fn_',fn),('sumiou_',si),('sumcov_',sm)]})
            cells.append(dict(plot=plot,arm='forestformer3d',state='successful_nonempty',
                predictions=tp+fp,reference_count=tp+fn,metrics=dict(mask=[mask],detection=[
                    dict(policy='max_agl',apex_TP=tp,apex_FP=fp,apex_FN=fn)])))
        rows=pipeline.pooled_metrics(dict(complete_detector_matrix=True,cells=cells))
        apex=next(r for r in rows if r['target']=='apex_max_agl')
        mask=next(r for r in rows if r['target']=='mask_iou_0.5')
        self.assertAlmostEqual(apex['recall'],.4); self.assertAlmostEqual(apex['F1'],8/15)
        self.assertAlmostEqual(mask['coverage'],.27); self.assertAlmostEqual(mask['PQ'],2.4/7.5)
        self.assertEqual(pipeline.pooled_metrics(dict(complete_detector_matrix=False)),[])


if __name__ == '__main__':
    unittest.main()
