<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TariffRate extends Model
{
    protected $table = 'tariff_rate';
    protected $primaryKey = 'hs_code';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;
}
