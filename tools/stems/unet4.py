import torch, torch.nn.functional as F

class UNet4(torch.nn.Module):
    """Spleeter U-Net (4stems config: ELU activations), mask only.
    in: (B, 2, 512, 1024) magnitude  ->  out: (B, 2, 512, 1024) mask in 0..1"""
    def __init__(self):
        super().__init__()
        ch = [2, 16, 32, 64, 128, 256, 512]
        self.convs = torch.nn.ModuleList([torch.nn.Conv2d(ch[i], ch[i+1], 5, stride=2, padding=0) for i in range(6)])
        self.bns = torch.nn.ModuleList([torch.nn.BatchNorm2d(ch[i+1], eps=1e-3, momentum=0.01) for i in range(5)])
        up_in = [512, 512, 256, 128, 64, 32]; up_out = [256, 128, 64, 32, 16, 1]
        self.ups = torch.nn.ModuleList([torch.nn.ConvTranspose2d(up_in[i], up_out[i], 5, stride=2) for i in range(6)])
        self.ubns = torch.nn.ModuleList([torch.nn.BatchNorm2d(up_out[i], eps=1e-3, momentum=0.01) for i in range(6)])
        self.last = torch.nn.Conv2d(1, 2, kernel_size=4, dilation=2, padding=3)

    def forward(self, x):
        skips = []
        h = x
        for i in range(6):
            h = F.pad(h, (1, 2, 1, 2))
            h = self.convs[i](h)
            skips.append(h)
            if i < 5:
                h = F.elu(self.bns[i](h))
        for i in range(6):
            h = self.ups[i](h)[:, :, 1:-2, 1:-2]
            h = self.ubns[i](F.elu(h))
            if i < 5:
                h = torch.cat([skips[4 - i], h], dim=1)
        return torch.sigmoid(self.last(h))
