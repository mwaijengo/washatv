/** Tanzania mobile-money network from national `0XXXXXXXXX` phone. */
export type TzMobileNetwork = 'mpesa' | 'airtel' | 'tigo' | 'halotel' | 'unknown';

export function detectTzMobileNetwork(localPhone: string): TzMobileNetwork {
  let local = localPhone.replace(/\D/g, '');
  while (local.startsWith('255')) {
    local = local.slice(3);
  }
  while (local.startsWith('0')) {
    local = local.slice(1);
  }
  if (local.length !== 9 || !/^[67]\d{8}$/.test(local)) return 'unknown';
  local = `0${local}`;

  const prefix = local.slice(0, 3);
  if (['061', '062', '063'].includes(prefix)) return 'halotel';
  if (['065', '067', '071', '073', '077'].includes(prefix)) return 'tigo';
  if (['068', '069', '078'].includes(prefix)) return 'airtel';
  if (['074', '075', '076'].includes(prefix)) return 'mpesa';
  if (local.startsWith('06')) return 'halotel';
  if (local.startsWith('07')) return 'mpesa';
  return 'unknown';
}

export function mobileMoneyMethodLabel(network: TzMobileNetwork): string {
  switch (network) {
    case 'mpesa':
      return 'M-Pesa';
    case 'airtel':
      return 'Airtel Money';
    case 'tigo':
      return 'Mixx by Yas';
    case 'halotel':
      return 'Halotel';
    default:
      return 'Mobile Money';
  }
}

export function paymentPromptForPhone(localPhone: string): string {
  const network = detectTzMobileNetwork(localPhone);
  switch (network) {
    case 'mpesa':
      return 'Angalia simu yako — thibitisha PIN ya M-Pesa.';
    case 'airtel':
      return 'Angalia simu yako — thibitisha PIN ya Airtel Money.';
    case 'tigo':
      return 'Angalia simu yako — thibitisha PIN ya Mixx by Yas.';
    case 'halotel':
      return 'Angalia simu yako — thibitisha PIN ya Halotel.';
    default:
      return 'Angalia simu yako — thibitisha PIN (M-Pesa, Mixx, Airtel Money, Halotel).';
  }
}
