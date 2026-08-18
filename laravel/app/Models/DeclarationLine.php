<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DeclarationLine extends Model
{
    protected $table = 'declaration_line';
    public $timestamps = false;
    public $incrementing = false;

    public function tariff()
    {
        return $this->belongsTo(TariffRate::class, 'hs_code', 'hs_code');
    }
}
