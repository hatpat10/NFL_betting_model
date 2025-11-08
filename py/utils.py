import math

def normal_cdf(x):
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

def win_prob_from_margin(pred_margin, sigma=13.86):
    return normal_cdf(pred_margin / sigma)
