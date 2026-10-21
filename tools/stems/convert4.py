import numpy as np, torch, onnx, tensorflow as tf
from unet4 import UNet4
names = ['vocals', 'drums', 'bass', 'other']
ck = '4stems/model'
def v(n): return torch.from_numpy(np.ascontiguousarray(tf.train.load_variable(ck, n)))
def sfx(k): return '' if k == 0 else f'_{k}'
def load(i):
    net = UNet4(); sd = net.state_dict()
    c0, b0, t0 = 7 * i, 12 * i, 6 * i
    for j in range(6):
        sd[f'convs.{j}.weight'] = v(f'conv2d{sfx(c0+j)}/kernel').permute(3, 2, 0, 1)
        sd[f'convs.{j}.bias'] = v(f'conv2d{sfx(c0+j)}/bias')
        if j < 5:
            for a, b in [('weight','gamma'),('bias','beta'),('running_mean','moving_mean'),('running_var','moving_variance')]:
                sd[f'bns.{j}.{a}'] = v(f'batch_normalization{sfx(b0+j)}/{b}')
    for j in range(6):
        sd[f'ups.{j}.weight'] = v(f'conv2d_transpose{sfx(t0+j)}/kernel').permute(3, 2, 0, 1)
        sd[f'ups.{j}.bias'] = v(f'conv2d_transpose{sfx(t0+j)}/bias')
        for a, b in [('weight','gamma'),('bias','beta'),('running_mean','moving_mean'),('running_var','moving_variance')]:
            sd[f'ubns.{j}.{a}'] = v(f'batch_normalization{sfx(b0+6+j)}/{b}')
    sd['last.weight'] = v(f'conv2d{sfx(c0+6)}/kernel').permute(3, 2, 0, 1)
    sd['last.bias'] = v(f'conv2d{sfx(c0+6)}/bias')
    net.load_state_dict(sd); net.eval(); return net

np.random.seed(1)
x = (np.random.rand(1, 512, 1024, 2) * 0.3).astype(np.float32)
with tf.compat.v1.Session(graph=tf.Graph()) as sess:
    saver = tf.compat.v1.train.import_meta_graph('4stems/model.meta', clear_devices=True)
    saver.restore(sess, ck)
    g = sess.graph
    inp = g.get_tensor_by_name('strided_slice_3:0'); lp = g.get_tensor_by_name('keras_learning_phase:0')
    refs = sess.run([g.get_tensor_by_name(f'conv2d{sfx(7*i+6)}/Sigmoid:0') for i in range(4)], {inp: x, lp: False})
for i, name in enumerate(names):
    net = load(i)
    with torch.no_grad():
        y = net(torch.from_numpy(np.transpose(x, (0, 3, 1, 2)).copy())).numpy()
    diff = np.abs(np.transpose(refs[i], (0, 3, 1, 2)) - y).max()
    print(name, 'max diff', diff)
    assert diff < 2e-3, name
    torch.onnx.export(net, torch.randn(1, 2, 512, 1024), f'{name}.onnx', input_names=['mag'], output_names=['mask'],
                      dynamic_axes={'mag': {0: 'b'}, 'mask': {0: 'b'}}, opset_version=13, dynamo=False)
    onnx.checker.check_model(onnx.load(f'{name}.onnx'))
print('done')
