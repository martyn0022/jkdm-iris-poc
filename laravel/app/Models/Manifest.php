<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Manifest extends Model
{
    protected $table = 'manifest';
    protected $primaryKey = 'manifest_ref';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    public function consignments()
    {
        return $this->hasMany(ManifestConsignment::class, 'manifest_ref', 'manifest_ref')
                    ->orderBy('line_no');
    }
}
